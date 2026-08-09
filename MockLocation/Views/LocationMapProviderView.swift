import CoreLocation
import Foundation
import SwiftUI
import UIKit

enum MapSource: Hashable {
    case amap
    case baidu

    var title: String {
        switch self {
        case .amap:
            return "高德地图"
        case .baidu:
            return "百度地图"
        }
    }
}

struct LocationMapProviderView: UIViewRepresentable {
    let source: MapSource
    @Binding var coordinate: GeoCoordinate
    @Binding var title: String
    @Binding var mapError: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MapTileContainer {
        let container = MapTileContainer(source: source)
        let coordinator = context.coordinator
        container.onLayoutChange = { [weak coordinator] view in
            coordinator?.render(in: view, force: true)
        }
        container.onLoadSuccess = { [weak coordinator] in
            coordinator?.parent.mapError = nil
        }
        container.onLoadFailure = { [weak coordinator] error in
            guard let coordinator else { return }
            coordinator.parent.mapError = Coordinator.errorMessage(for: coordinator.parent.source, error: error)
        }

        let longPress = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))
        container.addGestureRecognizer(longPress)
        container.addGestureRecognizer(pan)
        container.addGestureRecognizer(pinch)
        coordinator.render(in: container, force: true)
        return container
    }

    func updateUIView(_ container: MapTileContainer, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render(in: container)
    }

    final class Coordinator: NSObject {
        var parent: LocationMapProviderView

        private var displayedCoordinate: GeoCoordinate?
        private var mapCenter: CLLocationCoordinate2D?
        private var zoomLevel: Int

        init(parent: LocationMapProviderView) {
            self.parent = parent
            zoomLevel = parent.source.initialZoom
        }

        func render(in container: MapTileContainer, force: Bool = false) {
            guard container.bounds.width > 1, container.bounds.height > 1 else { return }
            guard parent.coordinate.isValid else {
                parent.mapError = "坐标无效，无法加载地图。"
                return
            }

            let coordinateChanged = displayedCoordinate != parent.coordinate || mapCenter == nil
            let selectedCoordinate = parent.coordinate.clCoordinate
            if coordinateChanged {
                displayedCoordinate = parent.coordinate
                mapCenter = selectedCoordinate
            }
            guard let mapCenter else { return }

            if force || coordinateChanged {
                parent.mapError = nil
            }
            container.setMap(
                center: parent.source.worldPoint(forWGS84: mapCenter, zoom: zoomLevel),
                selected: parent.source.worldPoint(forWGS84: selectedCoordinate, zoom: zoomLevel),
                zoom: zoomLevel,
                force: force || coordinateChanged
            )
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let container = recognizer.view as? MapTileContainer else { return }
            let point = recognizer.location(in: container)
            let coordinate = parent.source.wgs84Coordinate(for: container.coordinateWorldPoint(at: point), zoom: zoomLevel)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }
            parent.coordinate = GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            parent.title = "地图选点"
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let container = recognizer.view as? MapTileContainer else { return }
            switch recognizer.state {
            case .began, .changed:
                container.setPanTranslation(recognizer.translation(in: container))
            case .ended:
                mapCenter = parent.source.wgs84Coordinate(for: container.currentCenterWorldPoint(), zoom: zoomLevel)
                render(in: container, force: true)
            case .cancelled, .failed:
                container.setPanTranslation(.zero)
            default:
                break
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .ended, let container = recognizer.view as? MapTileContainer else { return }
            if recognizer.scale >= 1.2 {
                zoomLevel = min(parent.source.zoomRange.upperBound, zoomLevel + 1)
            } else if recognizer.scale <= 0.8 {
                zoomLevel = max(parent.source.zoomRange.lowerBound, zoomLevel - 1)
            } else {
                return
            }
            render(in: container, force: true)
        }

        static func errorMessage(for source: MapSource, error: Error) -> String {
            let nsError = error as NSError
            return "\(source.title)加载失败（\(nsError.domain) \(nsError.code)）：\(nsError.localizedDescription)"
        }
    }
}

final class MapTileContainer: UIView {
    var onLayoutChange: ((MapTileContainer) -> Void)?
    var onLoadSuccess: (() -> Void)?
    var onLoadFailure: ((Error) -> Void)?

    private let source: MapSource
    private let tileLayer = UIView()
    private let pinView = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let attributionLabel = UILabel()
    private let imageCache = NSCache<NSString, UIImage>()
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    private var centerWorldPoint = CGPoint.zero
    private var selectedWorldPoint = CGPoint.zero
    private var zoomLevel = 16
    private var panTranslation = CGPoint.zero
    private var isConfigured = false
    private var displayedSize = CGSize.zero
    private var generation = 0
    private var tileViews: [MapTileKey: MapTileView] = [:]
    private var tasks: [MapTileKey: URLSessionDataTask] = [:]
    private var pendingTiles = Set<MapTileKey>()
    private var loadedTileCount = 0
    private var firstError: Error?

    init(source: MapSource, frame: CGRect = .zero) {
        self.source = source
        super.init(frame: frame)
        backgroundColor = .systemGray6
        clipsToBounds = true
        isMultipleTouchEnabled = true

        tileLayer.backgroundColor = .systemGray6
        tileLayer.clipsToBounds = true
        addSubview(tileLayer)

        pinView.backgroundColor = .systemRed
        pinView.layer.cornerRadius = 9
        pinView.isHidden = true
        addSubview(pinView)

        activityIndicator.hidesWhenStopped = true
        addSubview(activityIndicator)

        attributionLabel.text = source.title
        attributionLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        attributionLabel.textColor = .label
        attributionLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
        attributionLabel.layer.cornerRadius = 3
        attributionLabel.clipsToBounds = true
        addSubview(attributionLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tileLayer.frame = bounds
        activityIndicator.center = CGPoint(x: bounds.midX, y: bounds.midY)
        layoutAttribution()
        layoutTileFrames()

        if displayedSize != bounds.size {
            displayedSize = bounds.size
            onLayoutChange?(self)
        }
    }

    func setMap(center: CGPoint, selected: CGPoint, zoom: Int, force: Bool) {
        let mapChanged = !isConfigured
            || zoomLevel != zoom
            || abs(centerWorldPoint.x - center.x) > 0.1
            || abs(centerWorldPoint.y - center.y) > 0.1
            || abs(selectedWorldPoint.x - selected.x) > 0.1
            || abs(selectedWorldPoint.y - selected.y) > 0.1
        guard force || mapChanged else { return }

        centerWorldPoint = center
        selectedWorldPoint = selected
        zoomLevel = zoom
        panTranslation = .zero
        isConfigured = true
        reloadTiles()
    }

    func setPanTranslation(_ translation: CGPoint) {
        guard isConfigured else { return }
        panTranslation = translation
        layoutTileFrames()
    }

    func currentCenterWorldPoint() -> CGPoint {
        CGPoint(
            x: centerWorldPoint.x - panTranslation.x,
            y: centerWorldPoint.y - panTranslation.y
        )
    }

    func coordinateWorldPoint(at point: CGPoint) -> CGPoint {
        let center = currentCenterWorldPoint()
        return CGPoint(
            x: center.x - bounds.width / 2 + point.x,
            y: center.y - bounds.height / 2 + point.y
        )
    }

    private func reloadTiles() {
        guard isConfigured, bounds.width > 1, bounds.height > 1 else { return }

        generation += 1
        let activeGeneration = generation
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        tileViews.values.forEach { $0.imageView.removeFromSuperview() }
        tileViews.removeAll()
        pendingTiles.removeAll()
        loadedTileCount = 0
        firstError = nil
        activityIndicator.startAnimating()

        let center = currentCenterWorldPoint()
        let tileSize = MapTileProjection.tileSize
        let topLeft = CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2)
        var startTileX = Int(floor(topLeft.x / tileSize))
        var endTileX = Int(floor((topLeft.x + bounds.width - 1) / tileSize))
        var startTileY = Int(floor(topLeft.y / tileSize))
        var endTileY = Int(floor((topLeft.y + bounds.height - 1) / tileSize))

        let yRange = source.rawTileYRange(zoom: zoomLevel)
        startTileY = max(startTileY, yRange.lowerBound)
        endTileY = min(endTileY, yRange.upperBound)

        guard startTileX <= endTileX, startTileY <= endTileY else {
            finishLoadingIfNeeded()
            return
        }

        for rawY in startTileY...endTileY {
            for rawX in startTileX...endTileX {
                let key = source.tileKey(rawX: rawX, rawY: rawY, zoom: zoomLevel)
                let imageView = UIImageView()
                imageView.contentMode = .scaleToFill
                tileLayer.addSubview(imageView)
                tileViews[key] = MapTileView(imageView: imageView, rawX: rawX, rawY: rawY)
                pendingTiles.insert(key)

                if let image = imageCache.object(forKey: key.cacheKey) {
                    imageView.image = image
                    pendingTiles.remove(key)
                    loadedTileCount += 1
                } else {
                    requestTile(key, generation: activeGeneration)
                }
            }
        }

        layoutTileFrames()
        finishLoadingIfNeeded()
    }

    private func requestTile(_ key: MapTileKey, generation: Int) {
        guard let url = source.tileURL(for: key) else {
            completeTile(key, generation: generation, image: nil, error: MapTileError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("MockLocation/1.0", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let result: Result<UIImage, Error>
            if let error {
                result = .failure(error)
            } else if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
                result = .failure(MapTileError.httpStatus(response.statusCode))
            } else if let data, let image = UIImage(data: data) {
                result = .success(image)
            } else {
                result = .failure(MapTileError.invalidImage)
            }

            DispatchQueue.main.async {
                switch result {
                case let .success(image):
                    self?.completeTile(key, generation: generation, image: image, error: nil)
                case let .failure(error):
                    self?.completeTile(key, generation: generation, image: nil, error: error)
                }
            }
        }
        tasks[key] = task
        task.resume()
    }

    private func completeTile(_ key: MapTileKey, generation: Int, image: UIImage?, error: Error?) {
        guard generation == self.generation else { return }
        tasks[key] = nil
        pendingTiles.remove(key)

        if let image {
            imageCache.setObject(image, forKey: key.cacheKey)
            tileViews[key]?.imageView.image = image
            loadedTileCount += 1
        } else if let error, firstError == nil {
            firstError = error
        }
        finishLoadingIfNeeded()
    }

    private func finishLoadingIfNeeded() {
        guard pendingTiles.isEmpty else { return }
        activityIndicator.stopAnimating()
        if loadedTileCount > 0 {
            onLoadSuccess?()
        } else {
            onLoadFailure?(firstError ?? MapTileError.noTileData)
        }
    }

    private func layoutTileFrames() {
        guard isConfigured else { return }
        let center = currentCenterWorldPoint()
        let tileSize = MapTileProjection.tileSize
        let topLeft = CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2)
        for tileView in tileViews.values {
            tileView.imageView.frame = CGRect(
                x: CGFloat(tileView.rawX) * tileSize - topLeft.x,
                y: CGFloat(tileView.rawY) * tileSize - topLeft.y,
                width: tileSize,
                height: tileSize
            )
        }

        pinView.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        pinView.center = CGPoint(
            x: selectedWorldPoint.x - center.x + bounds.width / 2,
            y: selectedWorldPoint.y - center.y + bounds.height / 2 - 9
        )
        pinView.isHidden = false
    }

    private func layoutAttribution() {
        attributionLabel.sizeToFit()
        let inset: CGFloat = 6
        attributionLabel.frame = CGRect(
            x: max(inset, bounds.maxX - attributionLabel.bounds.width - inset),
            y: max(inset, bounds.maxY - attributionLabel.bounds.height - inset),
            width: attributionLabel.bounds.width,
            height: attributionLabel.bounds.height
        )
    }
}

private extension MapSource {
    var initialZoom: Int { 16 }

    var zoomRange: ClosedRange<Int> {
        switch self {
        case .amap:
            return 3...18
        case .baidu:
            return 3...18
        }
    }

    func worldPoint(forWGS84 coordinate: CLLocationCoordinate2D, zoom: Int) -> CGPoint {
        switch self {
        case .amap:
            return AMapWebMercator.worldPoint(for: ChinaCoordinateConverter.wgs84ToGCJ02(coordinate), zoom: zoom)
        case .baidu:
            return BaiduMercator.worldPoint(for: ChinaCoordinateConverter.wgs84ToBD09(coordinate), zoom: zoom)
        }
    }

    func wgs84Coordinate(for worldPoint: CGPoint, zoom: Int) -> CLLocationCoordinate2D {
        switch self {
        case .amap:
            return ChinaCoordinateConverter.gcj02ToWGS84(AMapWebMercator.coordinate(for: worldPoint, zoom: zoom))
        case .baidu:
            return ChinaCoordinateConverter.bd09ToWGS84(BaiduMercator.coordinate(for: worldPoint, zoom: zoom))
        }
    }

    func rawTileYRange(zoom: Int) -> ClosedRange<Int> {
        switch self {
        case .amap:
            return 0...((1 << zoom) - 1)
        case .baidu:
            let maximumTile = BaiduMercator.maximumRawTileYCoordinate(zoom: zoom)
            return -maximumTile...maximumTile
        }
    }

    func tileKey(rawX: Int, rawY: Int, zoom: Int) -> MapTileKey {
        switch self {
        case .amap:
            let tileCount = 1 << zoom
            let remainder = rawX % tileCount
            let x = remainder >= 0 ? remainder : remainder + tileCount
            return MapTileKey(zoom: zoom, x: x, y: rawY)
        case .baidu:
            return MapTileKey(zoom: zoom, x: rawX, y: -rawY - 1)
        }
    }

    func tileURL(for key: MapTileKey) -> URL? {
        switch self {
        case .amap:
            let hostIndex = (key.x + key.y) % 4 + 1
            var components = URLComponents()
            components.scheme = "https"
            components.host = "webrd0\(hostIndex).is.autonavi.com"
            components.path = "/appmaptile"
            components.queryItems = [
                URLQueryItem(name: "lang", value: "zh_cn"),
                URLQueryItem(name: "size", value: "1"),
                URLQueryItem(name: "scale", value: "2"),
                URLQueryItem(name: "style", value: "8"),
                URLQueryItem(name: "x", value: String(key.x)),
                URLQueryItem(name: "y", value: String(key.y)),
                URLQueryItem(name: "z", value: String(key.zoom))
            ]
            return components.url
        case .baidu:
            let hostIndex = abs(key.x + key.y) % 4
            var components = URLComponents()
            components.scheme = "https"
            components.host = "maponline\(hostIndex).bdimg.com"
            components.path = "/tile/"
            components.queryItems = [
                URLQueryItem(name: "qt", value: "tile"),
                URLQueryItem(name: "x", value: String(key.x)),
                URLQueryItem(name: "y", value: String(key.y)),
                URLQueryItem(name: "z", value: String(key.zoom)),
                URLQueryItem(name: "styles", value: "pl"),
                URLQueryItem(name: "scaler", value: "2"),
                URLQueryItem(name: "p", value: "1")
            ]
            return components.url
        }
    }
}

private struct MapTileKey: Hashable {
    let zoom: Int
    let x: Int
    let y: Int

    var cacheKey: NSString { "\(zoom)/\(x)/\(y)" as NSString }
}

private struct MapTileView {
    let imageView: UIImageView
    let rawX: Int
    let rawY: Int
}

private enum MapTileError: LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case invalidImage
    case noTileData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无法创建地图请求。"
        case let .httpStatus(statusCode):
            return "地图服务器返回 HTTP \(statusCode)。"
        case .invalidImage:
            return "地图没有返回有效图片。"
        case .noTileData:
            return "地图没有返回底图数据。"
        }
    }
}

private enum MapTileProjection {
    static let tileSize: CGFloat = 256
}

private enum AMapWebMercator {
    private static let maximumLatitude = 85.051_128_78

    static func worldPoint(for coordinate: CLLocationCoordinate2D, zoom: Int) -> CGPoint {
        let latitude = min(max(coordinate.latitude, -maximumLatitude), maximumLatitude)
        let worldSize = Double(MapTileProjection.tileSize) * pow(2, Double(zoom))
        let latitudeRadians = latitude * Double.pi / 180
        let x = (coordinate.longitude + 180) / 360 * worldSize
        let y = (1 - log(tan(latitudeRadians) + 1 / cos(latitudeRadians)) / Double.pi) / 2 * worldSize
        return CGPoint(x: x, y: y)
    }

    static func coordinate(for point: CGPoint, zoom: Int) -> CLLocationCoordinate2D {
        let worldSize = Double(MapTileProjection.tileSize) * pow(2, Double(zoom))
        var x = Double(point.x).truncatingRemainder(dividingBy: worldSize)
        if x < 0 { x += worldSize }
        let y = min(max(Double(point.y), 0), worldSize)
        let longitude = x / worldSize * 360 - 180
        let mercatorY = y / worldSize
        let n = Double.pi - 2 * Double.pi * mercatorY
        let latitude = 180 / Double.pi * atan(0.5 * (exp(n) - exp(-n)))
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private enum BaiduMercator {
    private static let mcBands = [12_890_594.86, 8_362_377.87, 5_591_021, 3_481_989.83, 1_678_043.12, 0.0]
    private static let llBands = [75.0, 60.0, 45.0, 30.0, 15.0, 0.0]
    private static let mcToLL = [
        [1.410526172116255e-8, 0.00000898305509648872, -1.9939833816331, 200.9824383106796, -187.2403703815547, 91.6087516669843, -23.38765649603339, 2.57121317296198, -0.03801003308653, 17_337_981.2],
        [-7.435856389565537e-9, 0.000008983055097726239, -0.78625201886289, 96.32687599759846, -1.85204757529826, -59.36935905485877, 47.40033549296737, -16.50741931063887, 2.28786674699375, 10_260_144.86],
        [-3.030883460898826e-8, 0.00000898305509983578, 0.30071316287616, 59.74293618442277, 7.357984074871, -25.38371002664745, 13.45380521110908, -3.29883767235584, 0.32710905363475, 6_856_817.37],
        [-1.981981304930552e-8, 0.000008983055099779535, 0.03278182852591, 40.31678527705744, 0.65659298677277, -4.44255534477492, 0.85341911805263, 0.12923347998204, -0.04625736007561, 4_482_777.06],
        [3.09191371068437e-9, 0.000008983055096812155, 0.00006995724062, 23.10934304144901, -0.00023663490511, -0.6321817810242, -0.00663494467273, 0.03430082397953, -0.00466043876332, 2_555_164.4],
        [2.890871144776878e-9, 0.000008983055095805407, -3.068298e-8, 7.47137025468032, -0.00000353937994, -0.02145144861037, -0.00001234426596, 0.00010322952773, -0.00000323890364, 826_088.5]
    ]
    private static let llToMC = [
        [-0.0015702102444, 111_320.7020616939, 1_704_480_524_535_203.0, -10_338_987_376_042_340.0, 26_112_667_856_603_880.0, -35_149_675_196_675_700.0, 26_595_700_719_602_410.0, -10_724_184_411_424_040.0, 1_800_819_912_950_474.0, 82.5],
        [0.0008277824516172526, 111_320.7020463578, 647_795_574.6671607, -4_082_003_173.641316, 10_774_905_663.51142, -15_171_875_531.51559, 12_053_065_338.62167, -5_124_939_663.577472, 913_311_935.9512032, 67.5],
        [0.00337398766765, 111_320.7020202162, 4_481_351.045890365, -23_393_751.19931662, 79_682_215.47186455, -115_964_993.2797253, 97_236_711.15602145, -43_661_946.33752821, 8_477_230.501135234, 52.5],
        [0.00220636496208, 111_320.7020209128, 51_751.86112841131, 3_796_837.749470245, 992_013.7397791013, -1_221_952.21711287, 1_340_652.697009075, -620_943.6990984312, 144_416.9293806241, 37.5],
        [-0.0003441963504368392, 111_320.7020576856, 278.2353980772752, 2_485_758.690035394, 6_070.750963243378, 54_821.18345352118, 9_540.606633304236, -2_710.55326746645, 1_405.483844121726, 22.5],
        [-0.0003218135878613132, 111_320.7020701615, 0.00369383431289, 823_725.6402795718, 0.46104986909093, 2_351.343141331292, 1.58060784298199, 8.77738589078284, 0.37238884252424, 7.45]
    ]

    static func worldPoint(for coordinate: CLLocationCoordinate2D, zoom: Int) -> CGPoint {
        let projected = projectedPoint(for: coordinate)
        let resolution = resolution(for: zoom)
        return CGPoint(x: projected.x / resolution, y: -projected.y / resolution)
    }

    static func coordinate(for worldPoint: CGPoint, zoom: Int) -> CLLocationCoordinate2D {
        let resolution = resolution(for: zoom)
        return coordinate(forProjectedPoint: CGPoint(x: worldPoint.x * resolution, y: -worldPoint.y * resolution))
    }

    static func maximumRawTileYCoordinate(zoom: Int) -> Int {
        Int(ceil(mcBands[0] / resolution(for: zoom) / Double(MapTileProjection.tileSize)))
    }

    private static func projectedPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint {
        let longitude = loop(coordinate.longitude, min: -180, max: 180)
        let latitude = min(max(coordinate.latitude, -74), 74)
        return convert(CGPoint(x: longitude, y: latitude), with: forwardTable(for: latitude))
    }

    private static func coordinate(forProjectedPoint point: CGPoint) -> CLLocationCoordinate2D {
        let table = inverseTable(for: abs(Double(point.y)))
        let coordinate = convert(point, with: table)
        return CLLocationCoordinate2D(latitude: coordinate.y, longitude: coordinate.x)
    }

    private static func forwardTable(for latitude: Double) -> [Double] {
        for index in llBands.indices where latitude >= llBands[index] {
            return llToMC[index]
        }
        for index in llBands.indices.reversed() where latitude <= -llBands[index] {
            return llToMC[index]
        }
        return llToMC[llToMC.count - 1]
    }

    private static func inverseTable(for absoluteY: Double) -> [Double] {
        for index in mcBands.indices where absoluteY >= mcBands[index] {
            return mcToLL[index]
        }
        return mcToLL[mcToLL.count - 1]
    }

    private static func convert(_ point: CGPoint, with table: [Double]) -> CGPoint {
        let inputX = Double(point.x)
        let inputY = Double(point.y)
        let x = table[0] + table[1] * abs(inputX)
        let d = abs(inputY) / table[9]
        var y = table[2]
        var power = d
        for index in 3...8 {
            y += table[index] * power
            power *= d
        }
        return CGPoint(
            x: x * (inputX < 0 ? -1 : 1),
            y: y * (inputY < 0 ? -1 : 1)
        )
    }

    private static func resolution(for zoom: Int) -> Double {
        pow(2, Double(18 - zoom))
    }

    private static func loop(_ value: Double, min: Double, max: Double) -> Double {
        let width = max - min
        var result = value
        while result > max { result -= width }
        while result < min { result += width }
        return result
    }
}

private enum ChinaCoordinateConverter {
    private static let earthRadius = 6_378_245.0
    private static let eccentricitySquared = 0.006_693_421_622_965_943_23
    private static let bdOffsetFactor = Double.pi * 3_000 / 180

    static func wgs84ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard CLLocationCoordinate2DIsValid(coordinate), !isOutsideChina(coordinate) else { return coordinate }
        let delta = offset(for: coordinate)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + delta.latitude,
            longitude: coordinate.longitude + delta.longitude
        )
    }

    static func gcj02ToWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard CLLocationCoordinate2DIsValid(coordinate), !isOutsideChina(coordinate) else { return coordinate }
        var estimate = coordinate
        for _ in 0..<3 {
            let transformed = wgs84ToGCJ02(estimate)
            estimate = CLLocationCoordinate2D(
                latitude: estimate.latitude + coordinate.latitude - transformed.latitude,
                longitude: estimate.longitude + coordinate.longitude - transformed.longitude
            )
        }
        return estimate
    }

    static func wgs84ToBD09(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard CLLocationCoordinate2DIsValid(coordinate), !isOutsideChina(coordinate) else { return coordinate }
        return gcj02ToBD09(wgs84ToGCJ02(coordinate))
    }

    static func bd09ToWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard CLLocationCoordinate2DIsValid(coordinate), !isOutsideChina(coordinate) else { return coordinate }
        return gcj02ToWGS84(bd09ToGCJ02(coordinate))
    }

    private static func gcj02ToBD09(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = coordinate.longitude
        let y = coordinate.latitude
        let distance = sqrt(x * x + y * y) + 0.00002 * sin(y * bdOffsetFactor)
        let angle = atan2(y, x) + 0.000003 * cos(x * bdOffsetFactor)
        return CLLocationCoordinate2D(
            latitude: distance * sin(angle) + 0.006,
            longitude: distance * cos(angle) + 0.0065
        )
    }

    private static func bd09ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = coordinate.longitude - 0.0065
        let y = coordinate.latitude - 0.006
        let distance = sqrt(x * x + y * y) - 0.00002 * sin(y * bdOffsetFactor)
        let angle = atan2(y, x) - 0.000003 * cos(x * bdOffsetFactor)
        return CLLocationCoordinate2D(
            latitude: distance * sin(angle),
            longitude: distance * cos(angle)
        )
    }

    private static func offset(for coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = coordinate.longitude - 105
        let y = coordinate.latitude - 35
        var latitudeOffset = transformLatitude(x, y)
        var longitudeOffset = transformLongitude(x, y)
        let radians = coordinate.latitude * Double.pi / 180
        var magic = sin(radians)
        magic = 1 - eccentricitySquared * magic * magic
        let sqrtMagic = sqrt(magic)
        latitudeOffset = latitudeOffset * 180 / ((earthRadius * (1 - eccentricitySquared)) / (magic * sqrtMagic) * Double.pi)
        longitudeOffset = longitudeOffset * 180 / (earthRadius / sqrtMagic * cos(radians) * Double.pi)
        return CLLocationCoordinate2D(latitude: latitudeOffset, longitude: longitudeOffset)
    }

    private static func isOutsideChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.longitude < 72.004 || coordinate.longitude > 137.8347 || coordinate.latitude < 0.8293 || coordinate.latitude > 55.8271
    }

    private static func transformLatitude(_ x: Double, _ y: Double) -> Double {
        var result = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20 * sin(6 * x * Double.pi) + 20 * sin(2 * x * Double.pi)) * 2 / 3
        result += (20 * sin(y * Double.pi) + 40 * sin(y / 3 * Double.pi)) * 2 / 3
        result += (160 * sin(y / 12 * Double.pi) + 320 * sin(y * Double.pi / 30)) * 2 / 3
        return result
    }

    private static func transformLongitude(_ x: Double, _ y: Double) -> Double {
        var result = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20 * sin(6 * x * Double.pi) + 20 * sin(2 * x * Double.pi)) * 2 / 3
        result += (20 * sin(x * Double.pi) + 40 * sin(x / 3 * Double.pi)) * 2 / 3
        result += (150 * sin(x / 12 * Double.pi) + 300 * sin(x / 30 * Double.pi)) * 2 / 3
        return result
    }
}

import CoreLocation
import Foundation
import SwiftUI
import UIKit

struct LocationAMapView: UIViewRepresentable {
    @Binding var coordinate: GeoCoordinate
    @Binding var title: String
    @Binding var mapError: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> AMapTileContainer {
        let container = AMapTileContainer()
        let coordinator = context.coordinator
        container.onLayoutChange = { [weak coordinator] view in
            coordinator?.render(in: view, force: true)
        }
        container.onLoadSuccess = { [weak coordinator] in
            coordinator?.parent.mapError = nil
        }
        container.onLoadFailure = { [weak coordinator] error in
            coordinator?.parent.mapError = Coordinator.errorMessage(for: error)
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

    func updateUIView(_ container: AMapTileContainer, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render(in: container)
    }

    final class Coordinator: NSObject {
        var parent: LocationAMapView

        private var displayedCoordinate: GeoCoordinate?
        private var mapCenter: CLLocationCoordinate2D?
        private var zoomLevel = 16

        init(parent: LocationAMapView) {
            self.parent = parent
        }

        func render(in container: AMapTileContainer, force: Bool = false) {
            guard container.bounds.width > 1, container.bounds.height > 1 else { return }
            guard parent.coordinate.isValid else {
                parent.mapError = "坐标无效，无法加载地图。"
                return
            }

            let coordinateChanged = displayedCoordinate != parent.coordinate || mapCenter == nil
            let selectedCoordinate = AMapCoordinateConverter.wgs84ToGCJ02(parent.coordinate.clCoordinate)
            if coordinateChanged {
                displayedCoordinate = parent.coordinate
                mapCenter = selectedCoordinate
            }
            guard let mapCenter else { return }

            if force || coordinateChanged {
                parent.mapError = nil
            }
            container.setMap(
                center: AMapWebMercator.worldPoint(for: mapCenter, zoom: zoomLevel),
                selected: AMapWebMercator.worldPoint(for: selectedCoordinate, zoom: zoomLevel),
                zoom: zoomLevel,
                force: force || coordinateChanged
            )
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let container = recognizer.view as? AMapTileContainer else { return }
            let point = recognizer.location(in: container)
            let gcjCoordinate = container.coordinate(at: point)
            let wgsCoordinate = AMapCoordinateConverter.gcj02ToWGS84(gcjCoordinate)
            guard CLLocationCoordinate2DIsValid(wgsCoordinate) else { return }
            parent.coordinate = GeoCoordinate(latitude: wgsCoordinate.latitude, longitude: wgsCoordinate.longitude)
            parent.title = "地图选点"
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let container = recognizer.view as? AMapTileContainer else { return }
            switch recognizer.state {
            case .began, .changed:
                container.setPanTranslation(recognizer.translation(in: container))
            case .ended:
                mapCenter = AMapWebMercator.coordinate(for: container.currentCenterWorldPoint(), zoom: zoomLevel)
                render(in: container, force: true)
            case .cancelled, .failed:
                container.setPanTranslation(.zero)
            default:
                break
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .ended, let container = recognizer.view as? AMapTileContainer else { return }
            if recognizer.scale >= 1.2 {
                zoomLevel = min(18, zoomLevel + 1)
            } else if recognizer.scale <= 0.8 {
                zoomLevel = max(3, zoomLevel - 1)
            } else {
                return
            }
            render(in: container, force: true)
        }

        static func errorMessage(for error: Error) -> String {
            let nsError = error as NSError
            return "高德地图加载失败（\(nsError.domain) \(nsError.code)）：\(nsError.localizedDescription)"
        }
    }
}

final class AMapTileContainer: UIView {
    var onLayoutChange: ((AMapTileContainer) -> Void)?
    var onLoadSuccess: (() -> Void)?
    var onLoadFailure: ((Error) -> Void)?

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
    private var tileViews: [AMapTileKey: AMapTileView] = [:]
    private var tasks: [AMapTileKey: URLSessionDataTask] = [:]
    private var pendingTiles = Set<AMapTileKey>()
    private var loadedTileCount = 0
    private var firstError: Error?

    override init(frame: CGRect) {
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

        attributionLabel.text = "高德地图"
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

    func coordinate(at point: CGPoint) -> CLLocationCoordinate2D {
        let center = currentCenterWorldPoint()
        let worldPoint = CGPoint(
            x: center.x - bounds.width / 2 + point.x,
            y: center.y - bounds.height / 2 + point.y
        )
        return AMapWebMercator.coordinate(for: worldPoint, zoom: zoomLevel)
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
        let tileSize = AMapWebMercator.tileSize
        let tileCount = 1 << zoomLevel
        let topLeft = CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2)
        let startTileX = Int(floor(topLeft.x / tileSize))
        let endTileX = Int(floor((topLeft.x + bounds.width - 1) / tileSize))
        let startTileY = max(0, Int(floor(topLeft.y / tileSize)))
        let endTileY = min(tileCount - 1, Int(floor((topLeft.y + bounds.height - 1) / tileSize)))

        guard startTileY <= endTileY else {
            finishLoadingIfNeeded()
            return
        }

        for rawY in startTileY...endTileY {
            for rawX in startTileX...endTileX {
                let key = AMapTileKey(zoom: zoomLevel, x: wrappedTileX(rawX, tileCount: tileCount), y: rawY)
                let imageView = UIImageView()
                imageView.contentMode = .scaleToFill
                tileLayer.addSubview(imageView)
                tileViews[key] = AMapTileView(imageView: imageView, rawX: rawX, rawY: rawY)
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

    private func requestTile(_ key: AMapTileKey, generation: Int) {
        guard let url = AMapTileURL.makeURL(for: key) else {
            completeTile(key, generation: generation, image: nil, error: AMapTileError.invalidURL)
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
                result = .failure(AMapTileError.httpStatus(response.statusCode))
            } else if let data, let image = UIImage(data: data) {
                result = .success(image)
            } else {
                result = .failure(AMapTileError.invalidImage)
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

    private func completeTile(_ key: AMapTileKey, generation: Int, image: UIImage?, error: Error?) {
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
            onLoadFailure?(firstError ?? AMapTileError.noTileData)
        }
    }

    private func layoutTileFrames() {
        guard isConfigured else { return }
        let center = currentCenterWorldPoint()
        let tileSize = AMapWebMercator.tileSize
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

    private func wrappedTileX(_ x: Int, tileCount: Int) -> Int {
        let remainder = x % tileCount
        return remainder >= 0 ? remainder : remainder + tileCount
    }
}

private struct AMapTileKey: Hashable {
    let zoom: Int
    let x: Int
    let y: Int

    var cacheKey: NSString { "\(zoom)/\(x)/\(y)" as NSString }
}

private struct AMapTileView {
    let imageView: UIImageView
    let rawX: Int
    let rawY: Int
}

private enum AMapTileError: LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case invalidImage
    case noTileData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无法创建高德地图请求。"
        case let .httpStatus(statusCode):
            return "高德地图服务器返回 HTTP \(statusCode)。"
        case .invalidImage:
            return "高德地图没有返回有效图片。"
        case .noTileData:
            return "高德地图没有返回底图数据。"
        }
    }
}

private enum AMapTileURL {
    static func makeURL(for key: AMapTileKey) -> URL? {
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
    }
}

private enum AMapWebMercator {
    static let tileSize: CGFloat = 256
    private static let maximumLatitude = 85.051_128_78

    static func worldPoint(for coordinate: CLLocationCoordinate2D, zoom: Int) -> CGPoint {
        let latitude = min(max(coordinate.latitude, -maximumLatitude), maximumLatitude)
        let worldSize = Double(tileSize) * pow(2, Double(zoom))
        let latitudeRadians = latitude * Double.pi / 180
        let x = (coordinate.longitude + 180) / 360 * worldSize
        let y = (1 - log(tan(latitudeRadians) + 1 / cos(latitudeRadians)) / Double.pi) / 2 * worldSize
        return CGPoint(x: x, y: y)
    }

    static func coordinate(for point: CGPoint, zoom: Int) -> CLLocationCoordinate2D {
        let worldSize = Double(tileSize) * pow(2, Double(zoom))
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

private enum AMapCoordinateConverter {
    private static let earthRadius = 6_378_245.0
    private static let eccentricitySquared = 0.006_693_421_622_965_943_23

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

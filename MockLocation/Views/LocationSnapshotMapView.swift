import MapKit
import SwiftUI
import UIKit

struct LocationSnapshotMapView: UIViewRepresentable {
    @Binding var coordinate: GeoCoordinate
    @Binding var title: String
    @Binding var mapError: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> SnapshotMapContainer {
        let container = SnapshotMapContainer()
        let coordinator = context.coordinator
        container.onLayoutChange = { [weak coordinator] view in
            coordinator?.render(in: view)
        }

        let longPress = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        container.addGestureRecognizer(longPress)
        container.addGestureRecognizer(UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:))))
        container.addGestureRecognizer(UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:))))
        coordinator.render(in: container, force: true)
        return container
    }

    func updateUIView(_ container: SnapshotMapContainer, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render(in: container)
    }

    final class Coordinator: NSObject {
        var parent: LocationSnapshotMapView
        private var displayedCoordinate: GeoCoordinate?
        private var region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            latitudinalMeters: 1_800,
            longitudinalMeters: 1_800
        )
        private var snapshotter: MKMapSnapshotter?
        private var renderSequence = 0
        private var renderedSize = CGSize.zero
        private var mapLoadFailed = false
        private var panStartRegion: MKCoordinateRegion?
        private var pinchStartRegion: MKCoordinateRegion?

        init(parent: LocationSnapshotMapView) {
            self.parent = parent
        }

        func render(in container: SnapshotMapContainer, force: Bool = false) {
            let size = container.bounds.size
            guard size.width > 1, size.height > 1 else { return }

            let coordinateChanged = displayedCoordinate != parent.coordinate
            if coordinateChanged {
                region = MKCoordinateRegion(
                    center: parent.coordinate.clCoordinate,
                    latitudinalMeters: 1_800,
                    longitudinalMeters: 1_800
                )
                displayedCoordinate = parent.coordinate
            }

            if coordinateChanged || force {
                mapLoadFailed = false
            }

            guard force || coordinateChanged || renderedSize != size || (container.imageView.image == nil && !mapLoadFailed) else { return }
            renderedSize = size
            renderSequence += 1
            let sequence = renderSequence
            snapshotter?.cancel()

            let options = MKMapSnapshotter.Options()
            options.region = region
            options.mapType = .standard
            options.showsPointsOfInterest = true
            options.size = size
            options.scale = UIScreen.main.scale

            container.beginLoading()
            parent.mapError = nil
            let snapshotter = MKMapSnapshotter(options: options)
            self.snapshotter = snapshotter
            snapshotter.start { [weak self, weak container] snapshot, error in
                DispatchQueue.main.async {
                    guard let self, let container, sequence == self.renderSequence else { return }
                    guard let snapshot else {
                        container.endLoading()
                        self.mapLoadFailed = true
                        self.parent.mapError = self.mapErrorMessage(for: error)
                        return
                    }

                    container.imageView.image = snapshot.image
                    container.updatePin(at: snapshot.point(for: self.parent.coordinate.clCoordinate))
                    container.endLoading()
                    self.mapLoadFailed = false
                    self.parent.mapError = nil
                }
            }
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let container = recognizer.view as? SnapshotMapContainer else { return }
            let point = recognizer.location(in: container)
            let mapCoordinate = coordinate(for: point, in: container)
            guard CLLocationCoordinate2DIsValid(mapCoordinate) else { return }
            parent.coordinate = GeoCoordinate(latitude: mapCoordinate.latitude, longitude: mapCoordinate.longitude)
            parent.title = "地图选点"
            displayedCoordinate = parent.coordinate
            render(in: container, force: true)
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let container = recognizer.view as? SnapshotMapContainer else { return }
            switch recognizer.state {
            case .began:
                panStartRegion = region
            case .ended, .cancelled, .failed:
                guard let startRegion = panStartRegion else { return }
                let translation = recognizer.translation(in: container)
                let mapRect = mapRect(for: startRegion)
                let center = MKMapPoint(startRegion.center)
                let point = MKMapPoint(
                    x: clampedX(center.x - Double(translation.x / container.bounds.width) * mapRect.size.width),
                    y: clampedY(center.y - Double(translation.y / container.bounds.height) * mapRect.size.height)
                )
                region.center = point.coordinate
                panStartRegion = nil
                render(in: container, force: true)
            default:
                break
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let container = recognizer.view as? SnapshotMapContainer else { return }
            switch recognizer.state {
            case .began:
                pinchStartRegion = region
            case .ended, .cancelled, .failed:
                guard let startRegion = pinchStartRegion else { return }
                let scale = min(max(recognizer.scale, 0.25), 4)
                region.span.latitudeDelta = min(max(startRegion.span.latitudeDelta / scale, 0.002), 120)
                region.span.longitudeDelta = min(max(startRegion.span.longitudeDelta / scale, 0.002), 180)
                pinchStartRegion = nil
                render(in: container, force: true)
            default:
                break
            }
        }

        private func coordinate(for point: CGPoint, in container: SnapshotMapContainer) -> CLLocationCoordinate2D {
            let mapRect = mapRect(for: region)
            let x = clampedX(mapRect.origin.x + Double(point.x / container.bounds.width) * mapRect.size.width)
            let y = clampedY(mapRect.origin.y + Double(point.y / container.bounds.height) * mapRect.size.height)
            return MKMapPoint(x: x, y: y).coordinate
        }

        private func mapRect(for region: MKCoordinateRegion) -> MKMapRect {
            let halfLatitude = min(region.span.latitudeDelta / 2, 84)
            let halfLongitude = min(region.span.longitudeDelta / 2, 179)
            let topLeft = MKMapPoint(CLLocationCoordinate2D(
                latitude: min(region.center.latitude + halfLatitude, 85),
                longitude: region.center.longitude - halfLongitude
            ))
            let bottomRight = MKMapPoint(CLLocationCoordinate2D(
                latitude: max(region.center.latitude - halfLatitude, -85),
                longitude: region.center.longitude + halfLongitude
            ))
            return MKMapRect(
                x: topLeft.x,
                y: topLeft.y,
                width: max(bottomRight.x - topLeft.x, 1),
                height: max(bottomRight.y - topLeft.y, 1)
            )
        }

        private func clampedX(_ value: Double) -> Double {
            min(max(value, 0), MKMapRect.world.maxX)
        }

        private func clampedY(_ value: Double) -> Double {
            min(max(value, 0), MKMapRect.world.maxY)
        }

        private func mapErrorMessage(for error: Error?) -> String {
            guard let error else {
                return "兼容地图没有返回底图数据，请重试。"
            }

            let nsError = error as NSError
            var diagnostics = "\(nsError.domain) \(nsError.code)"
            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                diagnostics += "；底层错误：\(underlyingError.domain) \(underlyingError.code)"
            }
            return "兼容地图加载失败（\(diagnostics)）：\(nsError.localizedDescription)"
        }
    }
}

final class SnapshotMapContainer: UIView {
    let imageView = UIImageView()
    var onLayoutChange: ((SnapshotMapContainer) -> Void)?

    private let pinView = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var reportedSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        clipsToBounds = true

        imageView.contentMode = .scaleToFill
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)

        pinView.backgroundColor = .systemRed
        pinView.layer.cornerRadius = 9
        pinView.isHidden = true
        addSubview(pinView)

        activityIndicator.hidesWhenStopped = true
        addSubview(activityIndicator)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        activityIndicator.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if reportedSize != bounds.size {
            reportedSize = bounds.size
            onLayoutChange?(self)
        }
    }

    func beginLoading() {
        activityIndicator.startAnimating()
    }

    func endLoading() {
        activityIndicator.stopAnimating()
    }

    func updatePin(at point: CGPoint) {
        pinView.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        pinView.center = CGPoint(x: point.x, y: point.y - 9)
        pinView.isHidden = false
    }
}

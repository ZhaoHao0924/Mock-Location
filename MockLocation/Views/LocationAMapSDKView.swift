import AMapFoundationKit
import CoreLocation
import Foundation
import MAMapKit
import SwiftUI
import UIKit

enum AMapMapStyle: CaseIterable, Hashable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: Self { self }

    var title: String {
        switch self {
        case .standard:
            return "\u{6807}\u{51C6}"
        case .satellite:
            return "\u{536B}\u{661F}"
        case .hybrid:
            return "\u{6DF7}\u{5408}"
        }
    }

    fileprivate var nativeMapType: MAMapType {
        switch self {
        case .standard:
            return .standard
        case .satellite, .hybrid:
            return .satellite
        }
    }

    fileprivate var showsLabels: Bool {
        switch self {
        case .standard, .hybrid:
            return true
        case .satellite:
            return false
        }
    }
}

final class AMapMapContainerView: UIView {
    private(set) var mapView: MAMapView?
    var onMapReadyForDisplay: ((MAMapView) -> Void)?

    private var hasReportedDisplayReadiness = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutMapViewIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        layoutMapViewIfNeeded()
    }

    func attach(_ mapView: MAMapView) {
        self.mapView = mapView
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(mapView)
        layoutMapViewIfNeeded()
    }

    private func layoutMapViewIfNeeded() {
        guard let mapView, bounds.width >= 1, bounds.height >= 1 else { return }
        mapView.frame = bounds

        guard window != nil, !hasReportedDisplayReadiness else { return }
        hasReportedDisplayReadiness = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let mapView = self.mapView, self.window != nil else {
                self?.hasReportedDisplayReadiness = false
                return
            }
            mapView.frame = self.bounds
            self.onMapReadyForDisplay?(mapView)
        }
    }
}

struct LocationAMapSDKView: UIViewRepresentable {
    let style: AMapMapStyle
    @Binding var coordinate: GeoCoordinate
    @Binding var title: String
    @Binding var mapError: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> AMapMapContainerView {
        let container = AMapMapContainerView(frame: .zero)
        container.onMapReadyForDisplay = { [weak coordinator = context.coordinator] mapView in
            coordinator?.mapBecameReadyForDisplay(mapView)
        }
        AMapSDKConfiguration.configure()
        let resourceStatus = AMapMapViewFactory.prepareSDK()
        guard resourceStatus == 0 else {
            context.coordinator.setMapError("\(MapSource.amap.title) SDK 3D 资源校验失败（状态 \(resourceStatus)；\(AMapSDKConfiguration.diagnosticSummary)）。")
            return container
        }
        guard AMapSDKConfiguration.isApplied else {
            context.coordinator.setMapError("\(MapSource.amap.title) SDK API Key 未成功应用（\(AMapSDKConfiguration.diagnosticSummary)）。")
            return container
        }
        guard let mapView = AMapMapViewFactory.mapView(withFrame: .zero) else {
            context.coordinator.setMapError("\(MapSource.amap.title) SDK \u{65E0}\u{6CD5}\u{521B}\u{5EFA}\u{5730}\u{56FE}\u{89C6}\u{56FE}\u{3002}")
            return container
        }

        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.zoomLevel = 16
        context.coordinator.register(mapView)
        container.attach(mapView)

        return container
    }

    func updateUIView(_ container: AMapMapContainerView, context: Context) {
        context.coordinator.parent = self
        guard let mapView = container.mapView else {
            context.coordinator.setMapError("\(MapSource.amap.title) SDK \u{65E0}\u{6CD5}\u{521B}\u{5EFA}\u{5730}\u{56FE}\u{89C6}\u{56FE}\u{3002}")
            return
        }
        context.coordinator.updateMapIfDisplayed(mapView)
    }

    final class Coordinator: NSObject, MAMapViewDelegate {
        var parent: LocationAMapSDKView

        private static let mapSelectionTitle = "地图选点"
        private static let pinReuseIdentifier = "MockLocationSelectionPin"

        private var annotation: MAPointAnnotation?
        private var displayedCoordinate: GeoCoordinate?
        /// The coordinate this map itself just published. While it is pending,
        /// the SwiftUI round-trip must not recenter: tapping near an edge would
        /// otherwise yank the view out from under the finger that just tapped.
        private var mapOriginCoordinate: GeoCoordinate?
        private weak var registeredMapView: MAMapView?
        private var mapIsReadyForDisplay = false
        private var didInitializeMap = false
        private var didStartLoadingMap = false
        private var didFinishLoadingMap = false
        private var didFailLoadingMap = false
        private var successfulTileCount = 0
        private var failedTileCount = 0
        private var didReportLoadWatchdog = false
        private var loadWatchdog: DispatchWorkItem?

        init(parent: LocationAMapSDKView) {
            self.parent = parent
        }

        deinit {
            loadWatchdog?.cancel()
        }

        func register(_ mapView: MAMapView) {
            registeredMapView = mapView
            mapView.tileLoadCallback = { [weak self] success, _, _ in
                DispatchQueue.main.async {
                    self?.recordTileLoad(success: success)
                }
            }
            // Start the watchdog immediately. This still reports a useful
            // error if SwiftUI never gives the map container a visible layout.
            scheduleLoadWatchdog(for: mapView)
        }

        func mapBecameReadyForDisplay(_ mapView: MAMapView) {
            guard registeredMapView === mapView, !mapIsReadyForDisplay else { return }
            mapIsReadyForDisplay = true
            apply(style: parent.style, to: mapView)
            updateSelection(on: mapView, centerOnSelection: true)

            // Refresh only after SwiftUI has attached the map to a visible UIKit container.
            mapView.reloadInternalTexture()
            mapView.forceRefresh()
            scheduleLoadWatchdog(for: mapView)
        }

        func updateMapIfDisplayed(_ mapView: MAMapView) {
            guard registeredMapView === mapView, mapIsReadyForDisplay else { return }
            apply(style: parent.style, to: mapView)
            updateSelection(on: mapView, centerOnSelection: false)
        }

        func apply(style: AMapMapStyle, to mapView: MAMapView) {
            mapView.mapType = style.nativeMapType
            mapView.isShowsLabels = style.showsLabels
        }

        func updateSelection(on mapView: MAMapView, centerOnSelection: Bool) {
            guard parent.coordinate.isValid else {
                setMapError("\u{5750}\u{6807}\u{65E0}\u{6548}\u{FF0C}\u{65E0}\u{6CD5}\u{52A0}\u{8F7D}\u{5730}\u{56FE}\u{3002}")
                return
            }

            let selectionChanged = displayedCoordinate != parent.coordinate
            // Selections made on the map keep the camera where the user left it.
            // Selections arriving from search, favorites, coordinate entry or a
            // share still recenter, because their target may be off screen.
            let cameFromMap = mapOriginCoordinate == parent.coordinate
            if cameFromMap {
                mapOriginCoordinate = nil
            }
            let mapCoordinate = ChinaCoordinateConverter.wgs84ToGCJ02(parent.coordinate.clCoordinate)
            let marker = annotation ?? MAPointAnnotation()
            marker.coordinate = mapCoordinate
            marker.title = parent.title

            if annotation == nil {
                annotation = marker
                mapView.addAnnotation(marker)
            }

            if centerOnSelection || (selectionChanged && !cameFromMap) {
                mapView.centerCoordinate = mapCoordinate
            }
            displayedCoordinate = parent.coordinate
        }

        func mapViewDidFinishLoadingMap(_ mapView: MAMapView!) {
            didFinishLoadingMap = true
        }

        func mapViewDidFailLoadingMap(_ mapView: MAMapView!, withError error: Error!) {
            didFailLoadingMap = true
            loadWatchdog?.cancel()
            let nsError = error as NSError?
            let description = nsError?.localizedDescription ?? "\u{672A}\u{77E5}\u{9519}\u{8BEF}"
            let detail = nsError.map { "\($0.domain) / \($0.code)" } ?? "\u{65E0}\u{9519}\u{8BEF}\u{7801}"
            setMapError("\(MapSource.amap.title)\u{52A0}\u{8F7D}\u{5931}\u{8D25}\u{FF08}\(detail)\u{FF09}\u{FF1A}\(description)")
        }

        func mapViewWillStartLoadingMap(_ mapView: MAMapView!) {
            didStartLoadingMap = true
            if didReportLoadWatchdog {
                didReportLoadWatchdog = false
                setMapError(nil)
            }
        }

        func mapInitComplete(_ mapView: MAMapView!) {
            didInitializeMap = true
        }

        private func recordTileLoad(success: Bool) {
            if success {
                successfulTileCount += 1
                setMapError(nil)
            } else {
                failedTileCount += 1
            }
        }

        func mapView(_ mapView: MAMapView!, didChangeOpenGLESDisabled openGLESDisabled: Bool) {
            guard openGLESDisabled else { return }
            loadWatchdog?.cancel()
            setMapError("\(MapSource.amap.title) SDK \u{7684} iOS \u{56FE}\u{5F62}\u{6E32}\u{67D3}\u{5DF2}\u{88AB}\u{7981}\u{7528}\u{3002}\u{8BF7}\u{91CD}\u{542F}\u{8BBE}\u{5907}\u{540E}\u{91CD}\u{8BD5}\u{3002}")
        }

        /// Single delivery point for every selection made on the map itself.
        /// Marking `mapOriginCoordinate` is what stops `updateSelection` from
        /// recentering on the way back through SwiftUI.
        private func publishFromMap(_ gcj02Coordinate: CLLocationCoordinate2D) {
            let wgs84Coordinate = ChinaCoordinateConverter.gcj02ToWGS84(gcj02Coordinate)
            guard CLLocationCoordinate2DIsValid(wgs84Coordinate) else { return }

            let published = GeoCoordinate(
                latitude: wgs84Coordinate.latitude,
                longitude: wgs84Coordinate.longitude
            )
            mapOriginCoordinate = published
            parent.coordinate = published
            parent.title = Self.mapSelectionTitle
        }

        func mapView(_ mapView: MAMapView!, didSingleTappedAt coordinate: CLLocationCoordinate2D) {
            publishFromMap(coordinate)
        }

        func mapView(_ mapView: MAMapView!, didLongPressedAt coordinate: CLLocationCoordinate2D) {
            publishFromMap(coordinate)
        }

        func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
            guard annotation is MAPointAnnotation else { return nil }

            let identifier = Self.pinReuseIdentifier
            let pin: MAPinAnnotationView
            if let reused = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                as? MAPinAnnotationView {
                pin = reused
            } else {
                pin = MAPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }
            pin.annotation = annotation
            pin.canShowCallout = false
            pin.isDraggable = true
            pin.pinColor = .red
            return pin
        }

        func mapView(
            _ mapView: MAMapView!,
            annotationView view: MAAnnotationView!,
            didChange newState: MAAnnotationViewDragState,
            fromOldState oldState: MAAnnotationViewDragState
        ) {
            // Publish only once the drag settles, not on every intermediate frame.
            guard newState == .ending, let dragged = view.annotation else { return }
            publishFromMap(dragged.coordinate)
        }

        func setMapError(_ message: String?) {
            if Thread.isMainThread {
                parent.mapError = message
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.mapError = message
                }
            }
        }

        private func scheduleLoadWatchdog(for mapView: MAMapView) {
            loadWatchdog?.cancel()
            let watchdog = DispatchWorkItem { [weak self, weak mapView] in
                guard let self, let mapView, self.registeredMapView === mapView,
                      !self.didFailLoadingMap,
                      self.successfulTileCount == 0 else { return }

                self.didReportLoadWatchdog = true
                if self.failedTileCount > 0 {
                    self.setMapError("\(MapSource.amap.title) SDK 已请求地图瓦片，但全部加载失败（\(self.failedTileCount) 个）。\(AMapSDKConfiguration.diagnosticSummary)。")
                } else if self.didFinishLoadingMap {
                    // `mapViewDidFinishLoadingMap` fired, so the engine reports
                    // its map data as loaded. A blank screen after that points
                    // at the render surface never producing a frame.
                    //
                    // A zero `tileLoadCallback` count is NOT evidence that no
                    // tile was requested: that callback is not confirmed to be
                    // wired to the base map's internal pipeline, so it can read
                    // zero on a perfectly healthy map. Do not draw conclusions
                    // about authentication from it.
                    self.setMapError("\(MapSource.amap.title) SDK 报告地图数据已加载完成，但画面没有内容，通常是渲染器没有出帧。可在设置中切换 Metal 渲染开关后完全退出并重新打开应用。\(AMapSDKConfiguration.diagnosticSummary)。")
                } else if self.didInitializeMap && self.didStartLoadingMap {
                    self.setMapError("\(MapSource.amap.title) SDK \u{5DF2}\u{5F00}\u{59CB}\u{52A0}\u{8F7D}\u{4F46}\u{672A}\u{83B7}\u{5F97}\u{5730}\u{56FE}\u{6570}\u{636E}\u{3002}\u{8BF7}\u{68C0}\u{67E5}\u{7F51}\u{7EDC}\u{540E}\u{91CD}\u{8BD5}\u{3002}")
                } else if self.didInitializeMap {
                    self.setMapError("\(MapSource.amap.title) SDK \u{5DF2}\u{521D}\u{59CB}\u{5316}\u{FF0C}\u{4F46}\u{672A}\u{5F00}\u{59CB}\u{52A0}\u{8F7D}\u{5730}\u{56FE}\u{3002}\u{8BF7}\u{68C0}\u{67E5} API Key \u{7684} iOS Bundle ID \u{914D}\u{7F6E}\u{548C}\u{7F51}\u{7EDC}\u{3002}")
                } else {
                    self.setMapError("\(MapSource.amap.title) SDK \u{672A}\u{5B8C}\u{6210}\u{5730}\u{56FE}\u{5F15}\u{64CE}\u{521D}\u{59CB}\u{5316}\u{3002}\u{8BF7}\u{91CD}\u{542F}\u{8BBE}\u{5907}\u{540E}\u{91CD}\u{8BD5}\u{3002}")
                }
            }
            loadWatchdog = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: watchdog)
        }
    }
}

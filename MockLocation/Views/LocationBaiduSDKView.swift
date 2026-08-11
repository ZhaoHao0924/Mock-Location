import CoreLocation
import Foundation
import SwiftUI
import UIKit

/// 百度 renders through the native BaiduMapKit SDK. The SDK works in BD09LL
/// coordinates, so every selection crossing this boundary goes through
/// `ChinaCoordinateConverter` (the repository stores WGS-84).
struct LocationBaiduSDKView: UIViewRepresentable {
    @Binding var coordinate: GeoCoordinate
    @Binding var title: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> BMKMapView {
        BaiduSDKConfiguration.configure()
        // Recreating the view (map source switch, 刷新) is the user's retry
        // gesture: if the engine has been running without an auth verdict,
        // restart it for a fresh auth round.
        BaiduSDKConfiguration.restartIfAuthStalled()
        // A non-empty initialization frame matters on this device: the 高德
        // SDK's render surface never produced a frame when created at .zero
        // under SwiftUI, and both SDKs drive their surfaces the same way.
        let mapView = BMKMapView(frame: UIScreen.main.bounds)
        guard BaiduSDKConfiguration.isStarted else { return mapView }

        mapView.delegate = context.coordinator
        mapView.zoomLevel = 17
        mapView.viewWillAppear()
        context.coordinator.register(mapView)
        return mapView
    }

    func updateUIView(_ mapView: BMKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(mapView, centerOnSelection: false)
    }

    static func dismantleUIView(_ mapView: BMKMapView, coordinator: Coordinator) {
        mapView.viewWillDisappear()
        mapView.delegate = nil
    }

    final class Coordinator: NSObject, BMKMapViewDelegate {
        var parent: LocationBaiduSDKView

        private static let mapSelectionTitle = "地图选点"
        private static let pinReuseIdentifier = "MockLocationBaiduPin"

        private var annotation: BMKPointAnnotation?
        private var displayedCoordinate: GeoCoordinate?
        /// The coordinate this map itself just published. While it is pending,
        /// the SwiftUI round-trip must not recenter: tapping near an edge would
        /// otherwise yank the view out from under the finger that just tapped.
        private var mapOriginCoordinate: GeoCoordinate?
        private weak var registeredMapView: BMKMapView?
        private var didRefreshAfterAuth = false
        private var sdkStateObserver: NSObjectProtocol?

        init(parent: LocationBaiduSDKView) {
            self.parent = parent
        }

        deinit {
            if let sdkStateObserver {
                NotificationCenter.default.removeObserver(sdkStateObserver)
            }
        }

        func register(_ mapView: BMKMapView) {
            registeredMapView = mapView
            update(mapView, centerOnSelection: true)
            // A map created while the async auth verdict was still pending
            // draws nothing until it is refreshed, so refresh once when the
            // verdict lands (covers the save-key-then-open-map flow).
            sdkStateObserver = NotificationCenter.default.addObserver(
                forName: .baiduSDKStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshAfterAuthIfNeeded()
            }
            // SwiftUI attaches the view to the window after makeUIView
            // returns; a refresh scheduled past that point restarts the
            // engine's drawing on the now-visible surface.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak mapView] in
                mapView?.mapForceRefresh()
            }
        }

        private func refreshAfterAuthIfNeeded() {
            let delegate = BaiduSDKGeneralDelegate.shared
            guard !didRefreshAfterAuth,
                  delegate.didReceivePermissionVerdict,
                  delegate.permissionErrorCode == nil,
                  let mapView = registeredMapView else { return }
            didRefreshAfterAuth = true
            mapView.mapForceRefresh()
        }

        func update(_ mapView: BMKMapView, centerOnSelection: Bool) {
            guard registeredMapView === mapView, parent.coordinate.isValid else { return }

            let selectionChanged = displayedCoordinate != parent.coordinate
            // Selections made on the map keep the camera where the user left
            // it. Selections arriving from search, favorites, coordinate entry
            // or a share still recenter, because their target may be off screen.
            let cameFromMap = mapOriginCoordinate == parent.coordinate
            if cameFromMap {
                mapOriginCoordinate = nil
            }
            let mapCoordinate = ChinaCoordinateConverter.wgs84ToBD09(parent.coordinate.clCoordinate)
            let marker = annotation ?? BMKPointAnnotation()
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

        /// Single delivery point for every selection made on the map itself.
        /// Marking `mapOriginCoordinate` is what stops `update` from
        /// recentering on the way back through SwiftUI.
        private func publishFromMap(_ bd09Coordinate: CLLocationCoordinate2D, title: String? = nil) {
            let wgs84Coordinate = ChinaCoordinateConverter.bd09ToWGS84(bd09Coordinate)
            guard CLLocationCoordinate2DIsValid(wgs84Coordinate) else { return }

            let published = GeoCoordinate(
                latitude: wgs84Coordinate.latitude,
                longitude: wgs84Coordinate.longitude
            )
            mapOriginCoordinate = published
            parent.coordinate = published
            parent.title = title ?? Self.mapSelectionTitle
        }

        func mapView(_ mapView: BMKMapView, onClickedMapBlank coordinate: CLLocationCoordinate2D) {
            publishFromMap(coordinate)
        }

        func mapView(_ mapView: BMKMapView, onClickedMapPoi mapPoi: BMKMapPoi) {
            let poiTitle = mapPoi.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            publishFromMap(mapPoi.pt, title: (poiTitle?.isEmpty == false) ? poiTitle : nil)
        }

        // The lowercase `mapview` is 百度's own selector spelling for the
        // long-press callback; renaming it here would silently unhook it.
        func mapview(_ mapView: BMKMapView, onLongClick coordinate: CLLocationCoordinate2D) {
            publishFromMap(coordinate)
        }

        func mapView(_ mapView: BMKMapView, viewFor annotation: BMKAnnotation) -> BMKAnnotationView? {
            guard annotation is BMKPointAnnotation else { return nil }

            let identifier = Self.pinReuseIdentifier
            let pin: BMKPinAnnotationView
            if let reused = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                as? BMKPinAnnotationView {
                pin = reused
            } else {
                pin = BMKPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }
            pin.annotation = annotation
            pin.animatesDrop = false
            return pin
        }
    }
}

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
    @Binding var mapError: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> BMKMapView {
        BaiduSDKConfiguration.configure()
        // Recreating the view (map source switch, 刷新/重试) is the user's
        // retry gesture: if the engine has been running without an auth
        // verdict, restart it for a fresh auth round.
        BaiduSDKConfiguration.restartIfAuthStalled()
        // A non-empty initialization frame matters on this device: the 高德
        // SDK's render surface never produced a frame when created at .zero
        // under SwiftUI, and both SDKs drive their surfaces the same way.
        let mapView = BMKMapView(frame: UIScreen.main.bounds)
        guard BaiduSDKConfiguration.isStarted else {
            context.coordinator.setMapError("\(MapSource.baidu.title) SDK 未能启动（\(BaiduSDKConfiguration.diagnosticSummary)）。")
            return mapView
        }

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
        private var didFinishLoading = false
        private var didReportAuthError = false
        private var loadWatchdog: DispatchWorkItem?
        private var sdkStateObserver: NSObjectProtocol?

        init(parent: LocationBaiduSDKView) {
            self.parent = parent
        }

        deinit {
            loadWatchdog?.cancel()
            if let sdkStateObserver {
                NotificationCenter.default.removeObserver(sdkStateObserver)
            }
        }

        func register(_ mapView: BMKMapView) {
            registeredMapView = mapView
            update(mapView, centerOnSelection: true)
            // 鉴权是 start 后的异步回调，可能在任何时刻返回（包括
            // mapViewDidFinishLoading 之后）。即时上报，不依赖看门狗。
            sdkStateObserver = NotificationCenter.default.addObserver(
                forName: .baiduSDKStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshAuthState()
            }
            refreshAuthState()
            scheduleLoadWatchdog(for: mapView)
        }

        private func refreshAuthState() {
            let delegate = BaiduSDKGeneralDelegate.shared
            if let code = delegate.permissionErrorCode {
                didReportAuthError = true
                setMapError("\(MapSource.baidu.title) AK 校验未通过（错误码 \(code)）。请确认在百度开放平台创建的是「iOS 端」应用，且安全码与 Bundle ID 一致。\(BaiduSDKConfiguration.diagnosticSummary)。")
            } else if delegate.didReceivePermissionVerdict {
                // A clean verdict supersedes both a previous auth banner and
                // the watchdog's "no verdict" advisory.
                didReportAuthError = false
                setMapError(nil)
            }
        }

        func update(_ mapView: BMKMapView, centerOnSelection: Bool) {
            guard registeredMapView === mapView else { return }
            guard parent.coordinate.isValid else {
                setMapError("坐标无效，无法加载地图。")
                return
            }

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

        func mapViewDidFinishLoading(_ mapView: BMKMapView) {
            didFinishLoading = true
            // "加载完成" is the engine's claim about its data, not proof that
            // tiles rendered. While the auth verdict is still missing the
            // watchdog stays armed, because a verdict-less engine draws no
            // tiles and the user would otherwise see a silent blank map.
            if BaiduSDKGeneralDelegate.shared.didReceivePermissionVerdict {
                loadWatchdog?.cancel()
                if BaiduSDKGeneralDelegate.shared.permissionErrorCode == nil {
                    setMapError(nil)
                }
            }
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

        func setMapError(_ message: String?) {
            if Thread.isMainThread {
                parent.mapError = message
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.mapError = message
                }
            }
        }

        private func scheduleLoadWatchdog(for mapView: BMKMapView) {
            loadWatchdog?.cancel()
            let watchdog = DispatchWorkItem { [weak self, weak mapView] in
                guard let self, let mapView, self.registeredMapView === mapView else { return }
                let delegate = BaiduSDKGeneralDelegate.shared

                if let code = delegate.permissionErrorCode {
                    self.setMapError("\(MapSource.baidu.title) AK 校验未通过（错误码 \(code)）。请确认在百度开放平台创建的是「iOS 端」应用，且安全码与 Bundle ID 一致。\(BaiduSDKConfiguration.diagnosticSummary)。")
                } else if !delegate.didReceivePermissionVerdict {
                    self.setMapError("\(MapSource.baidu.title) SDK 鉴权一直没有返回结果，底图不会下发。点击「重试」可重启引擎重新鉴权。\(BaiduSDKConfiguration.diagnosticSummary)。")
                } else if let code = delegate.networkErrorCode {
                    self.setMapError("\(MapSource.baidu.title) SDK 联网失败（错误码 \(code)）。请检查网络后重试。\(BaiduSDKConfiguration.diagnosticSummary)。")
                } else if !self.didFinishLoading {
                    self.setMapError("\(MapSource.baidu.title) SDK 未在限定时间内完成地图加载。请检查网络与 AK 配置后重试。\(BaiduSDKConfiguration.diagnosticSummary)。")
                }
            }
            loadWatchdog = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: watchdog)
        }
    }
}

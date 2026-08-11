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
        /// `onDrawMapFrame` fires per rendered frame; one observation proves
        /// the render loop is alive at all.
        private var renderLoopObserved = false
        /// Set by `mapViewDidRenderValidData` — the engine's statement that
        /// real map content reached the screen. This, not
        /// `mapViewDidFinishLoading` (which per the header only means
        /// initialization finished), is the success signal.
        private var didRenderValidData = false
        private var lastRenderError: NSError?
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
            // SwiftUI attaches the view to the window after makeUIView
            // returns; a refresh scheduled past that point restarts the
            // engine's drawing on the now-visible surface.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak mapView] in
                mapView?.mapForceRefresh()
            }
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
                // The map may have been created while auth was still pending,
                // and the engine does not retry its tile fetches on its own.
                // A forced refresh gives the now-authorized engine a fresh
                // draw, and the watchdog a fresh window to judge it.
                if let mapView = registeredMapView, !didRenderValidData {
                    mapView.mapForceRefresh()
                    scheduleLoadWatchdog(for: mapView)
                }
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
            // Per the SDK header this only means "地图初始化完毕" — engine
            // initialization, not data on screen. Record it for diagnostics
            // and let the watchdog keep judging until valid data renders.
            didFinishLoading = true
        }

        func mapView(_ mapView: BMKMapView, onDrawMapFrame status: BMKMapStatus?) {
            renderLoopObserved = true
        }

        func mapViewDidRenderValidData(_ mapView: BMKMapView, withError error: Error?) {
            if let error = error as NSError?, error.code != 0 {
                lastRenderError = error
                setMapError("\(MapSource.baidu.title)绘制地图数据失败（\(error.domain) \(error.code)）：\(error.localizedDescription)")
                return
            }
            // Valid data is on screen — the one outcome that ends the hunt.
            didRenderValidData = true
            lastRenderError = nil
            loadWatchdog?.cancel()
            setMapError(nil)
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
                guard let self, let mapView, self.registeredMapView === mapView,
                      !self.didRenderValidData else { return }
                let delegate = BaiduSDKGeneralDelegate.shared

                if let code = delegate.permissionErrorCode {
                    self.setMapError("\(MapSource.baidu.title) AK 校验未通过（错误码 \(code)）。请确认在百度开放平台创建的是「iOS 端」应用，且安全码与 Bundle ID 一致。\(BaiduSDKConfiguration.diagnosticSummary)。")
                } else if !delegate.didReceivePermissionVerdict {
                    self.setMapError("\(MapSource.baidu.title) SDK 鉴权一直没有返回结果，底图不会下发。点击「重试」可重启引擎重新鉴权。\(BaiduSDKConfiguration.diagnosticSummary)。")
                } else if let code = delegate.networkErrorCode {
                    self.setMapError("\(MapSource.baidu.title) SDK 联网失败（错误码 \(code)）。请检查网络后重试。\(BaiduSDKConfiguration.diagnosticSummary)。")
                } else {
                    // Auth is clean yet nothing valid rendered. The render
                    // flags split the remaining suspects: a dead render loop
                    // is the GPU/surface, a live loop without valid data is
                    // the tile data path.
                    var renderState = "引擎初始化\(self.didFinishLoading ? "已完成" : "未完成")；渲染循环\(self.renderLoopObserved ? "运行中" : "未运行")；有效数据未绘制"
                    if let error = self.lastRenderError {
                        renderState += "；渲染错误 \(error.domain) \(error.code)"
                    }
                    self.setMapError("\(MapSource.baidu.title)鉴权已通过但底图没有绘制出来（\(renderState)）。\(BaiduSDKConfiguration.diagnosticSummary)。")
                }
            }
            loadWatchdog = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: watchdog)
        }
    }
}

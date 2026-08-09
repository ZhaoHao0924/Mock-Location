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

struct LocationAMapSDKView: UIViewRepresentable {
    let style: AMapMapStyle
    @Binding var coordinate: GeoCoordinate
    @Binding var title: String
    @Binding var mapError: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MAMapView {
        let mapView = MAMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.zoomLevel = 16
        context.coordinator.apply(style: style, to: mapView)
        context.coordinator.updateSelection(on: mapView, centerOnSelection: true)

        if !AMapSDKConfiguration.isConfigured {
            context.coordinator.setMapError("\(MapSource.amap.title) SDK \u{672A}\u{914D}\u{7F6E} API Key\u{3002}")
        }
        return mapView
    }

    func updateUIView(_ mapView: MAMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(style: style, to: mapView)
        context.coordinator.updateSelection(on: mapView, centerOnSelection: false)
    }

    final class Coordinator: NSObject, MAMapViewDelegate {
        var parent: LocationAMapSDKView

        private var annotation: MAPointAnnotation?
        private var displayedCoordinate: GeoCoordinate?

        init(parent: LocationAMapSDKView) {
            self.parent = parent
        }

        func apply(style: AMapMapStyle, to mapView: MAMapView) {
            mapView.mapType = style.nativeMapType
            mapView.showsLabels = style.showsLabels
        }

        func updateSelection(on mapView: MAMapView, centerOnSelection: Bool) {
            guard parent.coordinate.isValid else {
                setMapError("\u{5750}\u{6807}\u{65E0}\u{6548}\u{FF0C}\u{65E0}\u{6CD5}\u{52A0}\u{8F7D}\u{5730}\u{56FE}\u{3002}")
                return
            }

            let selectionChanged = displayedCoordinate != parent.coordinate
            let mapCoordinate = ChinaCoordinateConverter.wgs84ToGCJ02(parent.coordinate.clCoordinate)
            let marker = annotation ?? MAPointAnnotation()
            marker.coordinate = mapCoordinate
            marker.title = parent.title

            if annotation == nil {
                annotation = marker
                mapView.addAnnotation(marker)
            }

            if centerOnSelection || selectionChanged {
                mapView.centerCoordinate = mapCoordinate
            }
            displayedCoordinate = parent.coordinate
        }

        func mapViewDidFinishLoadingMap(_ mapView: MAMapView!) {
            setMapError(nil)
        }

        func mapViewDidFailLoadingMap(_ mapView: MAMapView!, withError error: Error!) {
            let description = (error as NSError?)?.localizedDescription ?? "\u{672A}\u{77E5}\u{9519}\u{8BEF}"
            setMapError("\(MapSource.amap.title)\u{52A0}\u{8F7D}\u{5931}\u{8D25}\u{FF1A}\(description)")
        }

        func mapView(_ mapView: MAMapView!, didLongPressedAt coordinate: CLLocationCoordinate2D) {
            let wgs84Coordinate = ChinaCoordinateConverter.gcj02ToWGS84(coordinate)
            guard CLLocationCoordinate2DIsValid(wgs84Coordinate) else { return }

            parent.coordinate = GeoCoordinate(
                latitude: wgs84Coordinate.latitude,
                longitude: wgs84Coordinate.longitude
            )
            parent.title = "\u{5730}\u{56FE}\u{9009}\u{70B9}"
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
    }
}

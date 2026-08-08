import MapKit
import SwiftUI

struct LocationMapView: UIViewRepresentable {
    @Binding var coordinate: GeoCoordinate
    @Binding var title: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .includingAll
        let recognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        recognizer.minimumPressDuration = 0.35
        mapView.addGestureRecognizer(recognizer)
        context.coordinator.updateAnnotation(on: mapView, coordinate: coordinate, title: title, recenter: true)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateAnnotation(on: mapView, coordinate: coordinate, title: title, recenter: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: LocationMapView
        private var displayedCoordinate: GeoCoordinate?

        init(parent: LocationMapView) {
            self.parent = parent
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let mapView = recognizer.view as? MKMapView else { return }
            let point = recognizer.location(in: mapView)
            let mapCoordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.coordinate = GeoCoordinate(latitude: mapCoordinate.latitude, longitude: mapCoordinate.longitude)
            parent.title = "Map pin"
            updateAnnotation(on: mapView, coordinate: parent.coordinate, title: parent.title, recenter: false)
        }

        func updateAnnotation(on mapView: MKMapView, coordinate: GeoCoordinate, title: String, recenter: Bool) {
            let changed = displayedCoordinate != coordinate
            guard changed || mapView.annotations.allSatisfy({ !($0 is MKPointAnnotation) }) else { return }
            displayedCoordinate = coordinate
            mapView.removeAnnotations(mapView.annotations.filter { $0 is MKPointAnnotation })
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate.clCoordinate
            annotation.title = title
            mapView.addAnnotation(annotation)
            if recenter || changed {
                mapView.setRegion(MKCoordinateRegion(center: coordinate.clCoordinate, latitudinalMeters: 1800, longitudinalMeters: 1800), animated: false)
            }
        }
    }
}

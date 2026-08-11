import CoreLocation
import Foundation

/// One-shot fetch of the device's real position, used at launch to center the
/// app on where the user actually is when no simulation is running.
final class CurrentLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((GeoCoordinate?) -> Void)?

    func requestOnce(_ completion: @escaping (GeoCoordinate?) -> Void) {
        guard self.completion == nil else { return }
        self.completion = completion
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            finish(nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(nil)
            return
        }
        finish(GeoCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ coordinate: GeoCoordinate?) {
        completion?(coordinate)
        completion = nil
    }
}

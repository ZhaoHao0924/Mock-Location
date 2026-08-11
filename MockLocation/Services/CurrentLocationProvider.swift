import CoreLocation
import Foundation

/// One-shot fetch of the device's real position — used at launch to center the
/// app on where the user actually is, and after the simulation stops to walk
/// the map back to the real fix.
final class CurrentLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((GeoCoordinate?) -> Void)?
    /// Fixes measured at or before this instant are discarded. While a
    /// simulation runs, locationd replays the mocked fix with current
    /// timestamps and keeps the last one cached after the stop, so only a
    /// measurement taken later than this instant proves to be the real
    /// position.
    private var acceptAfter: Date?
    private var timeoutWork: DispatchWorkItem?

    /// Accepts locationd's cached fix — launch centering wants speed.
    func requestOnce(_ completion: @escaping (GeoCoordinate?) -> Void) {
        begin(acceptAfter: nil, timeout: 15, completion: completion)
    }

    /// Accepts only fixes measured after `date`, staying subscribed until the
    /// real position reappears; completes nil when none arrives in time.
    func requestFresh(after date: Date, _ completion: @escaping (GeoCoordinate?) -> Void) {
        begin(acceptAfter: date, timeout: 20, completion: completion)
    }

    private func begin(acceptAfter: Date?, timeout: TimeInterval, completion: @escaping (GeoCoordinate?) -> Void) {
        // A newer request supersedes an in-flight one; the earlier caller gets
        // nil instead of the new request being silently dropped, which is what
        // previously made a second 关闭定位 tap during the wait do nothing.
        if let superseded = self.completion {
            self.completion = nil
            superseded(nil)
        }
        timeoutWork?.cancel()

        self.completion = completion
        self.acceptAfter = acceptAfter
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        let work = DispatchWorkItem { [weak self] in self?.finish(nil) }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            finish(nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            finish(nil)
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard completion != nil else { return }
        let accepted = locations.last { location in
            guard location.horizontalAccuracy >= 0 else { return false }
            guard let acceptAfter else { return true }
            return location.timestamp > acceptAfter
        }
        // Nothing acceptable yet (still the cached mocked fix): stay
        // subscribed until a real measurement arrives or the timeout fires.
        guard let location = accepted else { return }
        finish(GeoCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Reacquisition right after the simulation stops surfaces transient
        // kCLErrorLocationUnknown; per its documentation, keep waiting.
        if let clError = error as? CLError, clError.code == .locationUnknown { return }
        finish(nil)
    }

    private func finish(_ coordinate: GeoCoordinate?) {
        manager.stopUpdatingLocation()
        timeoutWork?.cancel()
        timeoutWork = nil
        acceptAfter = nil
        let completion = self.completion
        self.completion = nil
        completion?(coordinate)
    }
}

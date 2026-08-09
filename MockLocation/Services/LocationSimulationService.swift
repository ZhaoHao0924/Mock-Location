import Combine
import CoreLocation
import Foundation

final class LocationSimulationService: ObservableObject {
    enum State: Equatable {
        case idle
        case active(ActiveSimulation)
        case unavailable(String)
        case failed(String)

        var activeSimulation: ActiveSimulation? {
            if case let .active(simulation) = self { return simulation }
            return nil
        }
    }

    @Published private(set) var state: State = .idle

    func refreshAvailability() {
        if let message = PrivateLocationBridge.availabilityMessage() {
            state = .unavailable(message)
        } else if state.activeSimulation == nil {
            state = .idle
        }
    }

    func startPoint(_ coordinate: GeoCoordinate, title: String) {
        let locations = [CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)]
        start(locations: locations, active: ActiveSimulation(kind: .point, coordinate: coordinate, startedAt: Date(), title: title))
    }

    func startRoute(_ route: RoutePlan) {
        guard route.waypoints.count >= 2 else {
            state = .failed("A route needs at least two points.")
            return
        }
        let locations = RouteInterpolator.makeLocations(
            waypoints: route.waypoints,
            speedMetersPerSecond: route.speedMetersPerSecond
        )
        guard let first = route.waypoints.first else { return }
        start(locations: locations, active: ActiveSimulation(kind: .route, coordinate: first, startedAt: Date(), title: route.title))
    }

    func stop() {
        do {
            try PrivateLocationBridge.stop()
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func start(locations: [CLLocation], active: ActiveSimulation) {
        do {
            try PrivateLocationBridge.start(withLocations: locations)
            state = .active(active)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

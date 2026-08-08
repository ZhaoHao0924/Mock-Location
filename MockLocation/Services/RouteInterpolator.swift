import CoreLocation
import Foundation

enum RouteInterpolator {
    static func interpolatedCoordinates(
        waypoints: [GeoCoordinate],
        speedMetersPerSecond: Double,
        maximumSpacingMeters: Double = 25
    ) -> [GeoCoordinate] {
        guard waypoints.count > 1 else { return waypoints }
        let spacing = max(1, min(maximumSpacingMeters, max(1, speedMetersPerSecond)))
        var output: [GeoCoordinate] = [waypoints[0]]

        for (start, end) in zip(waypoints, waypoints.dropFirst()) {
            let distance = distanceMeters(from: start, to: end)
            let steps = max(1, Int(ceil(distance / spacing)))
            for index in 1...steps {
                output.append(interpolate(from: start, to: end, fraction: Double(index) / Double(steps)))
            }
        }
        return output
    }

    static func makeLocations(
        waypoints: [GeoCoordinate],
        speedMetersPerSecond: Double,
        startDate: Date = Date()
    ) -> [CLLocation] {
        let coordinates = interpolatedCoordinates(waypoints: waypoints, speedMetersPerSecond: speedMetersPerSecond)
        guard coordinates.count > 1 else {
            return coordinates.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        }

        var timestamp = startDate
        var locations: [CLLocation] = []
        for (index, coordinate) in coordinates.enumerated() {
            if index > 0 {
                let previous = coordinates[index - 1]
                timestamp = timestamp.addingTimeInterval(distanceMeters(from: previous, to: coordinate) / max(0.5, speedMetersPerSecond))
            }
            locations.append(
                CLLocation(
                    coordinate: coordinate.clCoordinate,
                    altitude: 0,
                    horizontalAccuracy: 5,
                    verticalAccuracy: 5,
                    course: -1,
                    speed: speedMetersPerSecond,
                    timestamp: timestamp
                )
            )
        }
        return locations
    }

    static func distanceMeters(from: GeoCoordinate, to: GeoCoordinate) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    private static func interpolate(from: GeoCoordinate, to: GeoCoordinate, fraction: Double) -> GeoCoordinate {
        GeoCoordinate(
            latitude: from.latitude + (to.latitude - from.latitude) * fraction,
            longitude: from.longitude + (to.longitude - from.longitude) * fraction
        )
    }
}

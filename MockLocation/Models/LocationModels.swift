import CoreLocation
import Foundation

struct GeoCoordinate: Codable, Hashable, Identifiable {
    let latitude: Double
    let longitude: Double

    var id: String { String(format: "%.6f,%.6f", latitude, longitude) }
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var isValid: Bool { (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    var displayValue: String { String(format: "%.6f, %.6f", latitude, longitude) }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct SavedLocation: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var coordinate: GeoCoordinate
    var createdAt: Date

    init(id: UUID = UUID(), title: String, coordinate: GeoCoordinate, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.coordinate = coordinate
        self.createdAt = createdAt
    }
}

struct RoutePlan: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var waypoints: [GeoCoordinate]
    var speedMetersPerSecond: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        waypoints: [GeoCoordinate],
        speedMetersPerSecond: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.waypoints = waypoints
        self.speedMetersPerSecond = speedMetersPerSecond
        self.createdAt = createdAt
    }
}

struct ActiveSimulation: Equatable {
    enum Kind: Equatable {
        case point
        case route
    }

    let kind: Kind
    let coordinate: GeoCoordinate
    let startedAt: Date
    let title: String
}

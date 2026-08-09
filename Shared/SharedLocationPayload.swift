import Foundation

enum SharedLocationStore {
    static let suiteName = "group.com.personal.mocklocation"
    static let pendingLocationKey = "pending-shared-location"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}

struct SharedLocationPayload: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let title: String
    let createdAt: Date

    init(latitude: Double, longitude: Double, title: String = "分享地点") {
        self.latitude = latitude
        self.longitude = longitude
        self.title = title
        self.createdAt = Date()
    }
}

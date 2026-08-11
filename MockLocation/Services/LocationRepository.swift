import Combine
import Foundation

final class LocationRepository: ObservableObject {
    @Published private(set) var favorites: [SavedLocation] = []
    @Published private(set) var recentLocations: [SavedLocation] = []
    @Published private(set) var savedRoutes: [RoutePlan] = []
    @Published var selectedCoordinate = GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
    @Published var selectedTitle = "默认地点"

    private enum Key {
        static let favorites = "favorites"
        static let recents = "recent-locations"
        static let routes = "saved-routes"
    }

    init() {
        favorites = load([SavedLocation].self, key: Key.favorites, fallback: [])
        recentLocations = load([SavedLocation].self, key: Key.recents, fallback: [])
        savedRoutes = load([RoutePlan].self, key: Key.routes, fallback: [])
    }

    func select(_ coordinate: GeoCoordinate, title: String = "未命名地点", addToHistory: Bool = true) {
        guard coordinate.isValid else { return }
        selectedCoordinate = coordinate
        selectedTitle = title.isEmpty ? "未命名地点" : title
        if addToHistory {
            addRecent(SavedLocation(title: selectedTitle, coordinate: coordinate))
        }
    }

    func addFavorite(title: String? = nil, coordinate: GeoCoordinate? = nil) {
        let location = SavedLocation(
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? selectedTitle,
            coordinate: coordinate ?? selectedCoordinate
        )
        if !favorites.contains(where: { $0.coordinate == location.coordinate }) {
            favorites.insert(location, at: 0)
            persist(favorites, key: Key.favorites)
        }
    }

    func renameFavorite(_ favorite: SavedLocation, title: String) {
        guard let index = favorites.firstIndex(where: { $0.id == favorite.id }),
              let newTitle = title.nonEmpty else { return }
        favorites[index].title = newTitle
        persist(favorites, key: Key.favorites)
    }

    func deleteFavorite(_ favorite: SavedLocation) {
        favorites.removeAll { $0.id == favorite.id }
        persist(favorites, key: Key.favorites)
    }

    func deleteRecent(_ recent: SavedLocation) {
        recentLocations.removeAll { $0.id == recent.id }
        persist(recentLocations, key: Key.recents)
    }

    func clearRecents() {
        recentLocations = []
        persist(recentLocations, key: Key.recents)
    }

    func saveRoute(title: String, waypoints: [GeoCoordinate], speed: Double) {
        guard waypoints.count >= 2 else { return }
        let route = RoutePlan(title: title.nonEmpty ?? "未命名路线", waypoints: waypoints, speedMetersPerSecond: speed)
        savedRoutes.insert(route, at: 0)
        persist(savedRoutes, key: Key.routes)
    }

    func deleteRoute(_ route: RoutePlan) {
        savedRoutes.removeAll { $0.id == route.id }
        persist(savedRoutes, key: Key.routes)
    }

    func consumePendingSharedLocation() {
        guard let data = SharedLocationStore.defaults.data(forKey: SharedLocationStore.pendingLocationKey),
              let payload = try? JSONDecoder().decode(SharedLocationPayload.self, from: data) else {
            return
        }
        SharedLocationStore.defaults.removeObject(forKey: SharedLocationStore.pendingLocationKey)
        select(GeoCoordinate(latitude: payload.latitude, longitude: payload.longitude), title: payload.title)
    }

    func consumeLocationURL(_ url: URL) {
        guard url.scheme == "mocklocation",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let latitude = components.queryItems?.first(where: { $0.name == "lat" })?.value.flatMap(Double.init),
              let longitude = components.queryItems?.first(where: { $0.name == "lon" })?.value.flatMap(Double.init) else {
            return
        }
        let title = components.queryItems?.first(where: { $0.name == "title" })?.value ?? "分享地点"
        select(GeoCoordinate(latitude: latitude, longitude: longitude), title: title)
    }

    private func addRecent(_ location: SavedLocation) {
        recentLocations.removeAll { $0.coordinate == location.coordinate }
        recentLocations.insert(location, at: 0)
        recentLocations = Array(recentLocations.prefix(24))
        persist(recentLocations, key: Key.recents)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String, fallback: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(type, from: data) else {
            return fallback
        }
        return value
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

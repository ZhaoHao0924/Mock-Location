import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            MapDashboardView()
                .tabItem { Label("Location", systemImage: "map") }
            RoutePlannerView()
                .tabItem { Label("Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
            SavedLocationsView()
                .tabItem { Label("Saved", systemImage: "star") }
            SettingsView()
                .tabItem { Label("Status", systemImage: "gearshape") }
        }
        .tint(.teal)
    }
}

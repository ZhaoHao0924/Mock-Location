import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var simulation: LocationSimulationService

    var body: some View {
        TabView {
            MapDashboardView()
                .tabItem { Label("地图", systemImage: "map") }
            RoutePlannerView()
                .tabItem { Label("路线", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
            SavedLocationsView()
                .tabItem { Label("收藏", systemImage: "star") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(.teal)
        .alert(item: $simulation.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("确定"))
            )
        }
    }
}

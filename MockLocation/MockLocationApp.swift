import SwiftUI

@main
struct MockLocationApp: App {
    @StateObject private var repository = LocationRepository()
    @StateObject private var simulation = LocationSimulationService()

    init() {
        AMapSDKConfiguration.configure()
        BaiduSDKConfiguration.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(repository)
                .environmentObject(simulation)
                .onOpenURL { url in
                    repository.consumeLocationURL(url)
                }
                .onAppear {
                    repository.consumePendingSharedLocation()
                    simulation.refreshAvailability()
                }
        }
    }
}

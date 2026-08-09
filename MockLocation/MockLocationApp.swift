import SwiftUI

@main
struct MockLocationApp: App {
    init() {
        AMapSDKConfiguration.configure()
    }

    @StateObject private var repository = LocationRepository()
    @StateObject private var simulation = LocationSimulationService()

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

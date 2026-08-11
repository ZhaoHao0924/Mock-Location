import SwiftUI

@main
struct MockLocationApp: App {
    @StateObject private var repository = LocationRepository()
    @StateObject private var simulation = LocationSimulationService()

    init() {
        AMapSDKConfiguration.configure()
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
                    // 百度's engine start must wait for the app to finish
                    // launching: started from App.init, its async auth verdict
                    // was observed to never arrive on-device.
                    BaiduSDKConfiguration.configure()
                    repository.consumePendingSharedLocation()
                    simulation.refreshAvailability()
                }
        }
    }
}

import SwiftUI
import UIKit

final class MockLocationAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AMapSDKConfiguration.configure()
        return true
    }
}

@main
struct MockLocationApp: App {
    @UIApplicationDelegateAdaptor(MockLocationAppDelegate.self) private var appDelegate

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

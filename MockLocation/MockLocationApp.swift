import SwiftUI

@main
struct MockLocationApp: App {
    @StateObject private var repository = LocationRepository()
    @StateObject private var simulation = LocationSimulationService()
    @StateObject private var currentLocation = CurrentLocationProvider()

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
                    showRealLocationIfIdle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .simulationDidStop)) { _ in
                    showRealLocation()
                }
        }
    }

    /// With no simulation running, the map should open on where the user
    /// really is rather than the built-in default. The result is applied only
    /// while the selection is still untouched, so a place the user picked in
    /// the meantime is never overridden.
    private func showRealLocationIfIdle() {
        guard simulation.state.activeSimulation == nil else { return }
        let untouchedTitle = repository.selectedTitle
        currentLocation.requestOnce { coordinate in
            guard let coordinate,
                  simulation.state.activeSimulation == nil,
                  repository.selectedTitle == untouchedTitle else { return }
            repository.select(coordinate, title: "当前位置", addToHistory: false)
        }
    }

    /// After the user explicitly stops the simulation, the map returns to the
    /// real position — that is the whole point of stopping. While simulating,
    /// locationd replays the mocked fix with current timestamps and keeps the
    /// last one cached, so a fix only counts as real when it was measured
    /// comfortably after the stop; the one-second margin also discards any
    /// straggler mock tick emitted before locationd processes the stop. The
    /// result is skipped if the user picked another place while waiting.
    private func showRealLocation() {
        let selectionAtStop = repository.selectedCoordinate
        currentLocation.requestFresh(after: Date().addingTimeInterval(1)) { coordinate in
            guard let coordinate,
                  simulation.state.activeSimulation == nil,
                  repository.selectedCoordinate == selectionAtStop else { return }
            repository.select(coordinate, title: "当前位置", addToHistory: false)
        }
    }
}

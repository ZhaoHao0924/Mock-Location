import Combine
import CoreLocation
import Foundation

struct SimulationNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

final class LocationSimulationService: ObservableObject {
    enum State: Equatable {
        case idle
        case active(ActiveSimulation)
        case unavailable(String)
        case failed(String)

        var activeSimulation: ActiveSimulation? {
            if case let .active(simulation) = self { return simulation }
            return nil
        }
    }

    @Published private(set) var state: State = .idle
    @Published var notice: SimulationNotice?

    func refreshAvailability() {
        if let message = PrivateLocationBridge.availabilityMessage() {
            state = .unavailable(message)
        } else if state.activeSimulation == nil {
            state = .idle
        }
    }

    func startPoint(_ coordinate: GeoCoordinate, title: String) {
        let locations = [CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)]
        start(locations: locations, active: ActiveSimulation(kind: .point, coordinate: coordinate, startedAt: Date(), title: title))
    }

    func startRoute(_ route: RoutePlan) {
        guard route.waypoints.count >= 2 else {
            let message = "路线至少需要两个点。"
            state = .failed(message)
            presentNotice(title: "启动失败", message: message)
            return
        }
        let locations = RouteInterpolator.makeLocations(
            waypoints: route.waypoints,
            speedMetersPerSecond: route.speedMetersPerSecond
        )
        guard let first = route.waypoints.first else { return }
        start(locations: locations, active: ActiveSimulation(kind: .route, coordinate: first, startedAt: Date(), title: route.title))
    }

    func stop() {
        do {
            try PrivateLocationBridge.stop()
            state = .idle
            presentNotice(title: "虚拟定位已关闭", message: "系统位置已恢复为真实位置。")
        } catch {
            let message = failureMessage(for: error)
            state = .failed(message)
            presentNotice(title: "关闭失败", message: message)
        }
    }

    private func start(locations: [CLLocation], active: ActiveSimulation) {
        do {
            try PrivateLocationBridge.start(with: locations)
            state = .active(active)
            let target = active.kind == .point ? "已切换到“\(active.title)”" : "路线模拟已开始。"
            presentNotice(title: "虚拟定位已开启", message: "\(target)\n其他应用现在会收到模拟位置。")
        } catch {
            let message = failureMessage(for: error)
            state = .failed(message)
            presentNotice(title: "启动失败", message: message)
        }
    }

    private func presentNotice(title: String, message: String) {
        notice = SimulationNotice(title: title, message: message)
    }

    private func failureMessage(for error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? "请检查 TrollStore 权限和系统版本后重试。" : description
    }
}

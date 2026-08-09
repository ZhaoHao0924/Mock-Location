import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var simulation: LocationSimulationService
    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationView {
            Form {
                Section("模拟状态") {
                    HStack {
                        Label("系统定位模拟", systemImage: "location.fill")
                        Spacer()
                        statusText
                    }
                    switch simulation.state {
                    case let .unavailable(message), let .failed(message):
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    default:
                        EmptyView()
                    }
                    Button {
                        simulation.refreshAvailability()
                    } label: {
                        Label("刷新状态", systemImage: "arrow.clockwise")
                    }
                }

                Section("安全操作") {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("停止并清除模拟", systemImage: "stop.circle")
                    }
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("停止虚拟定位？", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("停止并清除", role: .destructive) { simulation.stop() }
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var statusText: some View {
        switch simulation.state {
        case .idle:
            Text("未开启").foregroundColor(.secondary)
        case .active:
            Text("运行中").foregroundColor(.teal)
        case .unavailable:
            Text("不可用").foregroundColor(.orange)
        case .failed:
            Text("失败").foregroundColor(.red)
        }
    }
}

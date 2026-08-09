import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var simulation: LocationSimulationService
    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationView {
            Form {
                Section("Simulation runtime") {
                    HStack {
                        Label("Location simulation", systemImage: "location.fill")
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
                        Label("Check runtime", systemImage: "arrow.clockwise")
                    }
                }

                Section("Control") {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Stop and clear simulation", systemImage: "stop.circle")
                    }
                }
            }
            .navigationTitle("Status")
            .confirmationDialog("Stop location simulation?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("Stop simulation", role: .destructive) { simulation.stop() }
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var statusText: some View {
        switch simulation.state {
        case .idle:
            Text("Ready").foregroundColor(.secondary)
        case .active:
            Text("Active").foregroundColor(.teal)
        case .unavailable:
            Text("Unavailable").foregroundColor(.orange)
        case .failed:
            Text("Error").foregroundColor(.red)
        }
    }
}

import SwiftUI

struct RoutePlannerView: View {
    @EnvironmentObject private var repository: LocationRepository
    @EnvironmentObject private var simulation: LocationSimulationService
    @State private var waypoints: [GeoCoordinate] = []
    @State private var speed = 5.0
    @State private var routeName = "New route"

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text("\(Int(speed * 3.6)) km/h").foregroundColor(.secondary)
                    }
                    Slider(value: $speed, in: 1...30, step: 1)
                    HStack {
                        Button {
                            waypoints.append(repository.selectedCoordinate)
                        } label: {
                            Label("Add selected", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            waypoints.removeAll()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(waypoints.isEmpty)
                        .accessibilityLabel("Clear route")
                    }
                } header: {
                    Text("Route")
                }

                Section {
                    if waypoints.isEmpty {
                        Text("Add two or more points from the map.").foregroundColor(.secondary)
                    }
                    ForEach(Array(waypoints.enumerated()), id: \.offset) { index, coordinate in
                        HStack {
                            Text("\(index + 1)").foregroundColor(.secondary).frame(width: 24)
                            Text(coordinate.displayValue).font(.body.monospacedDigit())
                        }
                    }
                    .onDelete { offsets in
                        waypoints.remove(atOffsets: offsets)
                    }
                } header: {
                    Text("Waypoints")
                }

                Section {
                    TextField("Route name", text: $routeName)
                    Button {
                        let route = RoutePlan(title: routeName, waypoints: waypoints, speedMetersPerSecond: speed)
                        simulation.startRoute(route)
                    } label: {
                        Label("Start route", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(waypoints.count < 2)

                    Button {
                        repository.saveRoute(title: routeName, waypoints: waypoints, speed: speed)
                    } label: {
                        Label("Save route", systemImage: "square.and.arrow.down")
                    }
                    .disabled(waypoints.count < 2)
                }
            }
            .navigationTitle("Route")
            .toolbar { EditButton() }
        }
        .navigationViewStyle(.stack)
    }
}

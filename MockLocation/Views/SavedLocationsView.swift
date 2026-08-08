import SwiftUI

struct SavedLocationsView: View {
    @EnvironmentObject private var repository: LocationRepository
    @EnvironmentObject private var simulation: LocationSimulationService

    var body: some View {
        NavigationView {
            List {
                Section("Favorites") {
                    if repository.favorites.isEmpty {
                        Text("No saved locations.").foregroundColor(.secondary)
                    }
                    ForEach(repository.favorites) { location in
                        locationRow(location, allowDelete: true)
                    }
                }

                Section {
                    if repository.recentLocations.isEmpty {
                        Text("No recent locations.").foregroundColor(.secondary)
                    }
                    ForEach(repository.recentLocations) { location in
                        locationRow(location, allowDelete: false)
                    }
                } header: {
                    HStack {
                        Text("Recent")
                        Spacer()
                        Button("Clear") { repository.clearRecents() }
                            .font(.caption)
                            .disabled(repository.recentLocations.isEmpty)
                    }
                }

                Section("Saved routes") {
                    if repository.savedRoutes.isEmpty {
                        Text("No saved routes.").foregroundColor(.secondary)
                    }
                    ForEach(repository.savedRoutes) { route in
                        Button {
                            simulation.startRoute(route)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(route.title).foregroundColor(.primary)
                                Text("\(route.waypoints.count) points | \(Int(route.speedMetersPerSecond * 3.6)) km/h")
                                    .font(.footnote).foregroundColor(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { repository.deleteRoute(route) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved")
        }
        .navigationViewStyle(.stack)
    }

    private func locationRow(_ location: SavedLocation, allowDelete: Bool) -> some View {
        Button {
            repository.select(location.coordinate, title: location.title)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(location.title).foregroundColor(.primary)
                Text(location.coordinate.displayValue).font(.footnote.monospacedDigit()).foregroundColor(.secondary)
            }
        }
        .swipeActions {
            if allowDelete {
                Button(role: .destructive) { repository.deleteFavorite(location) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button {
                simulation.startPoint(location.coordinate, title: location.title)
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .tint(.teal)
        }
    }
}

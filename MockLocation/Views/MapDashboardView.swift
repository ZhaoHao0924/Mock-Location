import MapKit
import SwiftUI

struct MapDashboardView: View {
    @EnvironmentObject private var repository: LocationRepository
    @EnvironmentObject private var simulation: LocationSimulationService
    @StateObject private var search = LocationSearch()
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var showFavoriteName = false
    @State private var favoriteName = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                LocationMapView(coordinate: $repository.selectedCoordinate, title: $repository.selectedTitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                controlSurface
            }
            .navigationTitle("MockLocation")
            .searchable(text: $search.query, prompt: "Search places")
            .overlay(alignment: .top) {
                if !search.query.isEmpty && !search.suggestions.isEmpty {
                    searchResults
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        favoriteName = repository.selectedTitle
                        showFavoriteName = true
                    } label: {
                        Image(systemName: "star")
                    }
                    .accessibilityLabel("Save location")
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: syncCoordinateFields)
        .onChange(of: repository.selectedCoordinate) { _ in syncCoordinateFields() }
        .alert("Save location", isPresented: $showFavoriteName) {
            TextField("Name", text: $favoriteName)
            Button("Save") { repository.addFavorite(title: favoriteName) }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var searchResults: some View {
        List(Array(search.suggestions.enumerated()), id: \.offset) { _, suggestion in
            Button {
                search.resolve(suggestion) { coordinate, title in
                    repository.select(coordinate, title: title)
                    search.query = ""
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title).foregroundColor(.primary)
                    Text(suggestion.subtitle).font(.footnote).foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: 220)
        .background(.regularMaterial)
    }

    private var controlSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(repository.selectedTitle).font(.headline).lineLimit(1)
                    Text(repository.selectedCoordinate.displayValue).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                simulationIndicator
            }

            HStack(spacing: 8) {
                TextField("Latitude", text: $latitudeText)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                TextField("Longitude", text: $longitudeText)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                Button {
                    applyCoordinateFields()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Apply coordinates")
            }

            HStack(spacing: 10) {
                Button {
                    simulation.startPoint(repository.selectedCoordinate, title: repository.selectedTitle)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)

                Button(role: .destructive) {
                    simulation.stop()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Stop location simulation")
            }

            if case let .failed(message) = simulation.state {
                Text(message).font(.footnote).foregroundColor(.red)
            }
            if case let .unavailable(message) = simulation.state {
                Text(message).font(.footnote).foregroundColor(.orange)
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var simulationIndicator: some View {
        if let active = simulation.state.activeSimulation {
            Label(active.kind == .point ? "Active" : "Route", systemImage: "location.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.teal)
        } else {
            Label("Idle", systemImage: "location")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func syncCoordinateFields() {
        latitudeText = String(format: "%.6f", repository.selectedCoordinate.latitude)
        longitudeText = String(format: "%.6f", repository.selectedCoordinate.longitude)
    }

    private func applyCoordinateFields() {
        guard let latitude = Double(latitudeText), let longitude = Double(longitudeText) else { return }
        repository.select(GeoCoordinate(latitude: latitude, longitude: longitude), title: "Manual coordinate")
    }
}

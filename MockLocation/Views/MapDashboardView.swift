import MapKit
import SwiftUI

struct MapDashboardView: View {
    @EnvironmentObject private var repository: LocationRepository
    @EnvironmentObject private var simulation: LocationSimulationService
    @StateObject private var search = LocationSearch()
    @State private var mapDisplayMode: MapDisplayMode = .compatibility
    @State private var mapError: String?
    @State private var mapReloadToken = 0
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var showFavoriteName = false
    @State private var favoriteName = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Group {
                        if mapDisplayMode == .compatibility {
                            LocationSnapshotMapView(coordinate: $repository.selectedCoordinate, title: $repository.selectedTitle, mapError: $mapError)
                        } else {
                            LocationMapView(coordinate: $repository.selectedCoordinate, title: $repository.selectedTitle, mapError: $mapError)
                        }
                    }
                        .id(mapReloadToken)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let mapError {
                        mapErrorBanner(message: mapError)
                    }
                }

                controlSurface
            }
            .navigationTitle("虚拟定位")
            .searchable(text: $search.query, prompt: "搜索地点")
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
                    .accessibilityLabel("收藏当前位置")
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: syncCoordinateFields)
        .onChange(of: repository.selectedCoordinate) { _ in syncCoordinateFields() }
        .onChange(of: mapDisplayMode) { _ in
            mapError = nil
            mapReloadToken += 1
        }
        .alert("收藏地点", isPresented: $showFavoriteName) {
            TextField("名称", text: $favoriteName)
            Button("保存") { repository.addFavorite(title: favoriteName) }
            Button("取消", role: .cancel) { }
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

    private func mapErrorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "map.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("地图数据未加载")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Button("重试") {
                mapError = nil
                mapReloadToken += 1
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)
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

            Picker("地图模式", selection: $mapDisplayMode) {
                Text("兼容地图").tag(MapDisplayMode.compatibility)
                Text("互动地图").tag(MapDisplayMode.interactive)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                TextField("纬度", text: $latitudeText)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                TextField("经度", text: $longitudeText)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                Button {
                    applyCoordinateFields()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("应用坐标")
            }

            HStack(spacing: 10) {
                Button {
                    simulation.startPoint(repository.selectedCoordinate, title: repository.selectedTitle)
                } label: {
                    Label("开启定位", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)

                Button(role: .destructive) {
                    simulation.stop()
                } label: {
                    Label("关闭定位", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("关闭虚拟定位")
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
            Label(active.kind == .point ? "定位中" : "路线中", systemImage: "location.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.teal)
        } else {
            Label("未开启", systemImage: "location")
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
        repository.select(GeoCoordinate(latitude: latitude, longitude: longitude), title: "手动坐标")
    }
}

private enum MapDisplayMode: Hashable {
    case compatibility
    case interactive
}

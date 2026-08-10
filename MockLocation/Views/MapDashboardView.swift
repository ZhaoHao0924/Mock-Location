import SwiftUI

struct MapDashboardView: View {
    @EnvironmentObject private var repository: LocationRepository
    @EnvironmentObject private var simulation: LocationSimulationService
    @StateObject private var search = LocationSearch()
    @State private var amapStyle: AMapMapStyle = .standard
    @State private var mapSource: MapSource = .amap
    @State private var mapError: String?
    @State private var mapReloadToken = 0
    @AppStorage(AMapSDKConfiguration.apiKeyDefaultsKey) private var amapAPIKey = ""
    @AppStorage(AMapSDKConfiguration.useNativeSDKDefaultsKey) private var preferNativeAMapSDK = false
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var showFavoriteName = false
    @State private var favoriteName = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    mapSurface
                        .id(mapViewIdentity)
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
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        mapError = nil
                        mapReloadToken += 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("\u{5237}\u{65B0}\u{5730}\u{56FE}\u{6570}\u{636E}")

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
        .onAppear {
            syncCoordinateFields()
            normalizeStyleForProvider()
        }
        .onChange(of: repository.selectedCoordinate) { _ in syncCoordinateFields() }
        .onChange(of: mapSource) { _ in
            mapError = nil
            normalizeStyleForProvider()
        }
        .onChange(of: preferNativeAMapSDK) { _ in
            mapError = nil
            normalizeStyleForProvider()
        }
        .onChange(of: amapStyle) { _ in mapError = nil }
        .alert("收藏地点", isPresented: $showFavoriteName) {
            TextField("名称", text: $favoriteName)
            Button("保存") { repository.addFavorite(title: favoriteName) }
            Button("取消", role: .cancel) { }
        }
    }

    private var hasAMapAPIKey: Bool {
        !amapAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The native 3D SDK is opt-in. It needs an iOS-platform Key bound to this
    /// Bundle ID; without one 高德 rejects authentication and serves no tiles.
    private var usesNativeAMapSDK: Bool { mapSource == .amap && preferNativeAMapSDK }

    private var availableStyles: [AMapMapStyle] {
        usesNativeAMapSDK ? AMapMapStyle.allCases : AMapMapStyle.rasterRenderable
    }

    private var rasterStyle: AMapMapStyle {
        AMapMapStyle.rasterRenderable.contains(amapStyle) ? amapStyle : .satellite
    }

    private var mapViewIdentity: String {
        let effectiveStyle = usesNativeAMapSDK ? amapStyle : rasterStyle
        return "\(mapSource.title)-\(usesNativeAMapSDK ? "sdk" : "raster")-\(effectiveStyle.title)-\(mapReloadToken)"
    }

    @ViewBuilder
    private var mapSurface: some View {
        if usesNativeAMapSDK {
            if hasAMapAPIKey {
                LocationAMapSDKView(
                    style: amapStyle,
                    coordinate: $repository.selectedCoordinate,
                    title: $repository.selectedTitle,
                    mapError: $mapError
                )
            } else {
                amapKeyPlaceholder
            }
        } else {
            LocationMapProviderView(
                source: mapSource,
                style: rasterStyle,
                coordinate: $repository.selectedCoordinate,
                title: $repository.selectedTitle,
                mapError: $mapError
            )
        }
    }

    private func normalizeStyleForProvider() {
        guard !usesNativeAMapSDK, !AMapMapStyle.rasterRenderable.contains(amapStyle) else { return }
        amapStyle = .satellite
    }

    private var amapKeyPlaceholder: some View {
        Color.secondary.opacity(0.12)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "key.horizontal")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("未配置高德地图 iOS Key")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
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

            Picker("地图源", selection: $mapSource) {
                Text("高德地图").tag(MapSource.amap)
                Text("百度地图").tag(MapSource.baidu)
            }
            .pickerStyle(.segmented)

            if mapSource == .amap {
                Picker("\u{5730}\u{56FE}\u{6A21}\u{5F0F}", selection: $amapStyle) {
                    ForEach(availableStyles) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }


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

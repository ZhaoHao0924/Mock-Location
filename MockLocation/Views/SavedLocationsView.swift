import SwiftUI

struct SavedLocationsView: View {
    @EnvironmentObject private var repository: LocationRepository
    @EnvironmentObject private var simulation: LocationSimulationService

    var body: some View {
        NavigationView {
            List {
                Section("收藏地点") {
                    if repository.favorites.isEmpty {
                        Text("暂无收藏地点").foregroundColor(.secondary)
                    }
                    ForEach(repository.favorites) { location in
                        locationRow(location, allowDelete: true)
                    }
                }

                Section {
                    if repository.recentLocations.isEmpty {
                        Text("暂无最近使用地点").foregroundColor(.secondary)
                    }
                    ForEach(repository.recentLocations) { location in
                        locationRow(location, allowDelete: false)
                    }
                } header: {
                    HStack {
                        Text("最近使用")
                        Spacer()
                        Button("清空") { repository.clearRecents() }
                            .font(.caption)
                            .disabled(repository.recentLocations.isEmpty)
                    }
                }

                Section("已保存路线") {
                    if repository.savedRoutes.isEmpty {
                        Text("暂无已保存路线").foregroundColor(.secondary)
                    }
                    ForEach(repository.savedRoutes) { route in
                        Button {
                            simulation.startRoute(route)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(route.title).foregroundColor(.primary)
                                Text("\(route.waypoints.count) 个途经点 · \(Int(route.speedMetersPerSecond * 3.6)) 公里/小时")
                                    .font(.footnote).foregroundColor(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { repository.deleteRoute(route) } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("收藏与记录")
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
                    Label("删除", systemImage: "trash")
                }
            }
            Button {
                simulation.startPoint(location.coordinate, title: location.title)
            } label: {
                Label("开始定位", systemImage: "play.fill")
            }
            .tint(.teal)
        }
    }
}

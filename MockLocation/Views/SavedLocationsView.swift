import SwiftUI

struct SavedLocationsView: View {
    @EnvironmentObject private var repository: LocationRepository
    @EnvironmentObject private var simulation: LocationSimulationService
    @State private var renamingFavorite: SavedLocation?

    var body: some View {
        NavigationView {
            List {
                Section("收藏地点") {
                    if repository.favorites.isEmpty {
                        Text("暂无收藏地点").foregroundColor(.secondary)
                    }
                    ForEach(repository.favorites) { location in
                        locationRow(
                            location,
                            delete: { repository.deleteFavorite(location) },
                            rename: { renamingFavorite = location }
                        )
                    }
                }

                Section {
                    if repository.recentLocations.isEmpty {
                        Text("暂无最近使用地点").foregroundColor(.secondary)
                    }
                    ForEach(repository.recentLocations) { location in
                        locationRow(location, delete: { repository.deleteRecent(location) })
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
        .sheet(item: $renamingFavorite) { favorite in
            RenameFavoriteSheet(favorite: favorite) { newTitle in
                repository.renameFavorite(favorite, title: newTitle)
            }
        }
    }

    private func locationRow(
        _ location: SavedLocation,
        delete: @escaping () -> Void,
        rename: (() -> Void)? = nil
    ) -> some View {
        Button {
            repository.select(location.coordinate, title: location.title)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(location.title).foregroundColor(.primary)
                Text(location.coordinate.displayValue).font(.footnote.monospacedDigit()).foregroundColor(.secondary)
            }
        }
        .swipeActions {
            Button(role: .destructive, action: delete) {
                Label("删除", systemImage: "trash")
            }
            if let rename {
                Button(action: rename) {
                    Label("重命名", systemImage: "pencil")
                }
                .tint(.orange)
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

private struct RenameFavoriteSheet: View {
    let favorite: SavedLocation
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String

    init(favorite: SavedLocation, onSave: @escaping (String) -> Void) {
        self.favorite = favorite
        self.onSave = onSave
        _title = State(initialValue: favorite.title)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("别名") {
                    TextField("输入别名", text: $title)
                }
                Section("坐标") {
                    Text(favorite.coordinate.displayValue)
                        .font(.footnote.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("重命名收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(title)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

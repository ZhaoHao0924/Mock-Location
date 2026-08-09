import SwiftUI

struct RoutePlannerView: View {
    @EnvironmentObject private var repository: LocationRepository
    @EnvironmentObject private var simulation: LocationSimulationService
    @State private var waypoints: [GeoCoordinate] = []
    @State private var speed = 5.0
    @State private var routeName = "新路线"

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("速度")
                        Spacer()
                        Text("\(Int(speed * 3.6)) 公里/小时").foregroundColor(.secondary)
                    }
                    Slider(value: $speed, in: 1...30, step: 1)
                    HStack {
                        Button {
                            waypoints.append(repository.selectedCoordinate)
                        } label: {
                            Label("添加当前位置", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            waypoints.removeAll()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(waypoints.isEmpty)
                        .accessibilityLabel("清空途经点")
                    }
                } header: {
                    Text("路线设置")
                }

                Section {
                    if waypoints.isEmpty {
                        Text("在地图页选择地点后，添加为途经点。").foregroundColor(.secondary)
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
                    Text("途经点")
                }

                Section {
                    TextField("路线名称", text: $routeName)
                    Button {
                        let route = RoutePlan(title: routeName, waypoints: waypoints, speedMetersPerSecond: speed)
                        simulation.startRoute(route)
                    } label: {
                        Label("开始路线模拟", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(waypoints.count < 2)

                    Button {
                        repository.saveRoute(title: routeName, waypoints: waypoints, speed: speed)
                    } label: {
                        Label("保存路线", systemImage: "square.and.arrow.down")
                    }
                    .disabled(waypoints.count < 2)
                }
            }
            .navigationTitle("路线规划")
            .toolbar { EditButton() }
        }
        .navigationViewStyle(.stack)
    }
}

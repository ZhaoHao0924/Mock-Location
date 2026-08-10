import Foundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var simulation: LocationSimulationService
    @State private var showingResetConfirmation = false
    @State private var amapAPIKey = AMapSDKConfiguration.storedAPIKey
    @State private var amapKeySaveNotice: AMapKeySaveNotice?

    var body: some View {
        NavigationView {
            Form {
                amapKeySection

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
            .alert(item: $amapKeySaveNotice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("确定"))
                )
            }
            .onAppear {
                amapAPIKey = AMapSDKConfiguration.storedAPIKey
            }
        }
        .navigationViewStyle(.stack)
    }

    private var amapKeySection: some View {
        Section("高德地图") {
            SecureField("iOS Key", text: $amapAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)

            HStack(alignment: .firstTextBaseline) {
                Text("Bundle ID")
                Spacer()
                Text(Bundle.main.bundleIdentifier ?? "com.personal.mocklocation")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            Button {
                saveAMapAPIKey()
            } label: {
                Label("保存 Key", systemImage: "checkmark")
            }

            if AMapSDKConfiguration.isConfigured {
                Button(role: .destructive) {
                    amapAPIKey = ""
                    saveAMapAPIKey()
                } label: {
                    Label("清除 Key", systemImage: "trash")
                }
            }
        }
    }

    private func saveAMapAPIKey() {
        let keyWasCleared = amapAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let requiresRestart = AMapSDKConfiguration.saveAPIKey(amapAPIKey)
        amapAPIKey = AMapSDKConfiguration.storedAPIKey

        let title: String
        let message: String
        if requiresRestart {
            title = "需要重新打开应用"
            message = "新的高德地图 Key 会在重新打开应用后生效。"
        } else if keyWasCleared {
            title = "Key 已清除"
            message = "高德地图处于未配置状态。"
        } else {
            title = "Key 已保存"
            message = "返回地图页即可加载高德地图。"
        }
        amapKeySaveNotice = AMapKeySaveNotice(title: title, message: message)
    }

    private struct AMapKeySaveNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
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

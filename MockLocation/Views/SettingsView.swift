import Foundation
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var simulation: LocationSimulationService
    @State private var showingResetConfirmation = false
    @State private var amapAPIKey = AMapSDKConfiguration.storedAPIKey
    @AppStorage(AMapSDKConfiguration.metalEnabledDefaultsKey) private var metalEnabled = true
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
        Section {
            // Deliberately no .textContentType(.password): that marks the field
            // as a password, and iOS then gives the long-press menu over to
            // AutoFill, which can push 粘贴 out of the menu entirely.
            SecureField("iOS Key", text: $amapAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack(alignment: .firstTextBaseline) {
                Text("Key 长度")
                Spacer()
                Text(keyLengthState)
                    .font(.footnote)
                    .foregroundColor(isKeyLengthValid ? .secondary : .orange)
            }

            Button {
                pasteAMapAPIKeyFromClipboard()
            } label: {
                Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
            }

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

            Toggle(isOn: $metalEnabled) {
                Text("使用 Metal 渲染")
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Metal 设备")
                Spacer()
                Text(metalDeviceState)
                    .font(.footnote)
                    .foregroundColor(AMapMapViewFactory.isMetalAvailable() ? .secondary : .orange)
            }
        } header: {
            Text("高德地图")
        } footer: {
            Text("高德地图通过原生 3D SDK 渲染，必须配置 Key：平台为「iOS」且绑定的 Bundle ID 与上面一致。如果地图数据显示已加载完成但画面空白，那是渲染器没有出帧，可切换上面的 Metal 开关；切换后需要完全退出并重新打开应用才生效。")
                .font(.footnote)
        }
    }

    private var metalDeviceState: String {
        AMapMapViewFactory.isMetalAvailable() ? "可用" : "不可用"
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

    /// Reads the clipboard directly instead of relying on the long-press menu.
    /// Keys copied from the 高德 console often carry a trailing newline, so trim.
    private func pasteAMapAPIKeyFromClipboard() {
        guard let pasted = UIPasteboard.general.string else {
            amapKeySaveNotice = AMapKeySaveNotice(
                title: "剪贴板为空",
                message: "没有从剪贴板读到文本。请先在高德控制台复制 Key。"
            )
            return
        }
        amapAPIKey = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var keyLengthState: String {
        let count = amapAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).count
        return count == 0 ? "未输入" : "\(count) 位"
    }

    private var isKeyLengthValid: Bool {
        amapAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).count == 32
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

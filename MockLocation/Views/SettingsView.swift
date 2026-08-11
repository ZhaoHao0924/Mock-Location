import Foundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var simulation: LocationSimulationService
    @State private var showingResetConfirmation = false
    @State private var amapAPIKey = AMapSDKConfiguration.storedAPIKey
    @State private var baiduAPIKey = BaiduSDKConfiguration.storedAPIKey
    @State private var isEditingAMapKey = false
    @State private var isEditingBaiduKey = false
    @AppStorage(AMapSDKConfiguration.metalEnabledDefaultsKey) private var metalEnabled = true
    @State private var keySaveNotice: KeySaveNotice?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    KeyEditorRows(
                        keyLabel: "iOS Key",
                        keyText: $amapAPIKey,
                        isEditing: $isEditingAMapKey,
                        isConfigured: AMapSDKConfiguration.isConfigured,
                        storedValue: { AMapSDKConfiguration.storedAPIKey },
                        onSave: saveAMapAPIKey
                    )

                    Toggle(isOn: $metalEnabled) {
                        Text("使用 Metal 渲染")
                    }
                } header: {
                    Text("高德地图")
                } footer: {
                    Text("高德地图通过原生 3D SDK 渲染，必须配置 Key：平台为「iOS」且绑定的 Bundle ID 与上面一致。如果地图数据显示已加载完成但画面空白，可切换 Metal 开关；切换后需要完全退出并重新打开应用才生效。")
                        .font(.footnote)
                }

                Section {
                    KeyEditorRows(
                        keyLabel: "iOS AK",
                        keyText: $baiduAPIKey,
                        isEditing: $isEditingBaiduKey,
                        isConfigured: BaiduSDKConfiguration.isConfigured,
                        storedValue: { BaiduSDKConfiguration.storedAPIKey },
                        onSave: saveBaiduAPIKey
                    )
                } header: {
                    Text("百度地图")
                } footer: {
                    Text("百度地图通过原生 SDK 渲染，必须配置 AK：在百度地图开放平台创建「iOS 端」应用，安全码填写与上面一致的 Bundle ID。首次保存后返回地图页即可加载；修改已生效的 AK 需要完全退出并重新打开应用。")
                        .font(.footnote)
                }

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
            .alert(item: $keySaveNotice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("确定"))
                )
            }
            .onAppear {
                amapAPIKey = AMapSDKConfiguration.storedAPIKey
                baiduAPIKey = BaiduSDKConfiguration.storedAPIKey
            }
        }
        .navigationViewStyle(.stack)
    }

    /// The shared key-entry rows for both map providers. The field is locked
    /// until 编辑 is tapped, so a stored key cannot be mangled by a stray tap.
    /// Both providers bind their key to the same app Bundle ID (百度 calls it
    /// 安全码), so the row is labeled identically for both.
    private struct KeyEditorRows: View {
        let keyLabel: String
        @Binding var keyText: String
        @Binding var isEditing: Bool
        let isConfigured: Bool
        let storedValue: () -> String
        let onSave: () -> Void

        var body: some View {
            // A plain TextField, not SecureField. The Key lives in UserDefaults
            // as plaintext, so masking it bought no security while making paste
            // awkward and hiding whether a paste actually landed.
            TextField(keyLabel, text: $keyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .foregroundColor(isEditing ? .primary : .secondary)
                .disabled(!isEditing)

            HStack(alignment: .firstTextBaseline) {
                Text("Bundle ID")
                Spacer()
                Text(Bundle.main.bundleIdentifier ?? "com.personal.mocklocation")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if isEditing {
                Button {
                    onSave()
                    isEditing = false
                } label: {
                    Label("保存", systemImage: "checkmark")
                }

                Button {
                    keyText = storedValue()
                    isEditing = false
                } label: {
                    Label("取消", systemImage: "xmark")
                }

                if isConfigured {
                    Button(role: .destructive) {
                        keyText = ""
                        onSave()
                        isEditing = false
                    } label: {
                        Label("清除", systemImage: "trash")
                    }
                }
            } else {
                Button {
                    isEditing = true
                } label: {
                    Label("编辑", systemImage: "pencil")
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
        keySaveNotice = KeySaveNotice(title: title, message: message)
    }

    private func saveBaiduAPIKey() {
        let keyWasCleared = baiduAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let requiresRestart = BaiduSDKConfiguration.saveAPIKey(baiduAPIKey)
        baiduAPIKey = BaiduSDKConfiguration.storedAPIKey

        let title: String
        let message: String
        if requiresRestart {
            title = "需要重新打开应用"
            message = "新的百度地图 AK 会在重新打开应用后生效。"
        } else if keyWasCleared {
            title = "AK 已清除"
            message = "百度地图处于未配置状态。"
        } else {
            title = "AK 已保存"
            message = "返回地图页即可加载百度地图。"
        }
        keySaveNotice = KeySaveNotice(title: title, message: message)
    }

    private struct KeySaveNotice: Identifiable {
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

import Foundation
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var simulation: LocationSimulationService
    @State private var showingResetConfirmation = false
    @State private var amapAPIKey = AMapSDKConfiguration.storedAPIKey
    @State private var baiduAPIKey = BaiduSDKConfiguration.storedAPIKey
    @AppStorage(AMapSDKConfiguration.metalEnabledDefaultsKey) private var metalEnabled = true
    @State private var keySaveNotice: KeySaveNotice?
    @State private var baiduNetworkProbeResult: String?
    @State private var baiduNetworkProbeRunning = false

    var body: some View {
        NavigationView {
            Form {
                amapKeySection

                baiduKeySection

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

    private var amapKeySection: some View {
        Section {
            // A plain TextField, not SecureField. The Key lives in UserDefaults
            // as plaintext, so masking it bought no security while making paste
            // awkward and hiding whether a paste actually landed. Also no
            // .textContentType(.password): that marks the field as a password
            // and iOS hands the long-press menu to AutoFill, which can push
            // 粘贴 out of the menu entirely.
            TextField("iOS Key", text: $amapAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))

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

    private var baiduKeySection: some View {
        Section {
            TextField("iOS AK", text: $baiduAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))

            HStack(alignment: .firstTextBaseline) {
                Text("安全码 (Bundle ID)")
                Spacer()
                Text(Bundle.main.bundleIdentifier ?? "com.personal.mocklocation")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            Button {
                saveBaiduAPIKey()
            } label: {
                Label("保存 AK", systemImage: "checkmark")
            }

            if BaiduSDKConfiguration.isConfigured {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SDK 状态")
                    Text(BaiduSDKConfiguration.diagnosticSummary)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Button {
                    baiduNetworkProbeRunning = true
                    baiduNetworkProbeResult = nil
                    BaiduSDKConfiguration.probeNetwork { result in
                        baiduNetworkProbeRunning = false
                        baiduNetworkProbeResult = result
                    }
                } label: {
                    Label(
                        baiduNetworkProbeRunning ? "正在测试连通性…" : "测试百度服务连通性",
                        systemImage: "network"
                    )
                }
                .disabled(baiduNetworkProbeRunning)

                if let baiduNetworkProbeResult {
                    Text(baiduNetworkProbeResult)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                NavigationLink {
                    BaiduLogView()
                } label: {
                    Label("查看百度地图日志", systemImage: "doc.text.magnifyingglass")
                }

                Button(role: .destructive) {
                    baiduAPIKey = ""
                    saveBaiduAPIKey()
                } label: {
                    Label("清除 AK", systemImage: "trash")
                }
            }
        } header: {
            Text("百度地图")
        } footer: {
            Text("百度地图通过原生 SDK 渲染，必须配置 AK：在百度地图开放平台创建「iOS 端」应用，安全码填写与上面一致的 Bundle ID。首次保存后返回地图页即可加载；修改已生效的 AK 需要完全退出并重新打开应用。")
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

    private struct BaiduLogView: View {
        @State private var logText = ""

        var body: some View {
            ScrollView {
                Text(logText.isEmpty ? "正在读取日志……" : logText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .navigationTitle("百度地图日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = logText
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("复制全部日志")
                    Button {
                        loadLog()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新日志")
                }
            }
            .onAppear(perform: loadLog)
        }

        private func loadLog() {
            DispatchQueue.global(qos: .userInitiated).async {
                let text = BaiduSDKConfiguration.recentLogExcerpt()
                DispatchQueue.main.async {
                    logText = text.isEmpty ? "没有读到日志内容。" : text
                }
            }
        }
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

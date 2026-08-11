import Foundation
import Security

extension Notification.Name {
    /// Posted on the main queue whenever 百度's asynchronous auth/network
    /// callbacks change state, so live map views can surface the result
    /// immediately instead of waiting for a watchdog.
    static let baiduSDKStateDidChange = Notification.Name("baidu-sdk-state-did-change")
}

/// Receives the asynchronous key-validation and network callbacks that
/// `BMKMapManager.start` schedules. A non-zero permission code is the SDK's
/// verdict that the AK was rejected (wrong platform, or 安全码 not matching
/// this Bundle ID), so it is kept for diagnostics.
///
/// Every method carries an explicit `@objc`. Implicit inference would very
/// likely cover these, but the whole failure being investigated is "the SDK
/// never calls us back", and a selector mismatch produces exactly that
/// symptom. The annotation removes it from the list of suspects.
final class BaiduSDKGeneralDelegate: NSObject, BMKGeneralDelegate {
    static let shared = BaiduSDKGeneralDelegate()

    private(set) var permissionErrorCode: Int32?
    private(set) var networkErrorCode: Int32?
    /// True once `onGetPermissionState` has fired at all — distinguishes
    /// "validated successfully" from "no verdict yet" when both codes are nil.
    private(set) var didReceivePermissionVerdict = false
    private(set) var didReceiveNetworkVerdict = false

    /// A fresh auth round is starting; stale verdicts from the previous
    /// engine run must not satisfy the new one.
    func resetForRestart() {
        permissionErrorCode = nil
        networkErrorCode = nil
        didReceivePermissionVerdict = false
        didReceiveNetworkVerdict = false
    }

    @objc func onGetNetworkState(_ iError: Int32) {
        didReceiveNetworkVerdict = true
        networkErrorCode = iError == 0 ? nil : iError
        notifyStateChange()
    }

    @objc func onGetPermissionState(_ iError: Int32) {
        didReceivePermissionVerdict = true
        permissionErrorCode = iError == 0 ? nil : iError
        notifyStateChange()
    }

    private func notifyStateChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .baiduSDKStateDidChange, object: nil)
        }
    }
}

enum BaiduSDKConfiguration {
    static let apiKeyDefaultsKey = "baidu-sdk-api-key"

    /// `BMKMapManager` must stay alive for the whole process; releasing it
    /// tears down the map engine.
    private static var mapManager: BMKMapManager?
    private static var configuredAPIKey: String?
    private static var engineStartedAt: Date?
    /// How long a silent auth round can run before a restart is allowed.
    private static let authVerdictTimeout: TimeInterval = 15

    static var isConfigured: Bool { !storedAPIKey.isEmpty }
    /// True when the engine was started with the currently stored key. Like
    /// the 高德 flag, this only means the key was handed to the SDK; 百度
    /// validates it over the network and reports through `BMKGeneralDelegate`.
    static var isStarted: Bool {
        mapManager != nil && configuredAPIKey == storedAPIKey
    }
    static var storedAPIKey: String { apiKey }

    static var diagnosticSummary: String {
        let key = storedAPIKey
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let keySuffix = key.isEmpty ? "-" : String(key.suffix(4))
        var summary = "Bundle ID \(bundleID)；AK \(key.count) 位 / 末四位 \(keySuffix)；引擎\(isStarted ? "已启动" : "未启动")"
        let delegate = BaiduSDKGeneralDelegate.shared
        if let code = delegate.permissionErrorCode {
            summary += "；鉴权失败（错误码 \(code)）"
        } else if delegate.didReceivePermissionVerdict {
            summary += "；鉴权已通过"
        } else {
            summary += "；鉴权未返回结果"
        }
        if let code = delegate.networkErrorCode {
            summary += "；网络回调错误码 \(code)"
        } else if delegate.didReceiveNetworkVerdict {
            summary += "；网络回调正常"
        } else {
            summary += "；网络回调未返回"
        }
        let cuid = (BMKMapManager.getCUID() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        summary += "；CUID \(cuid.isEmpty ? "为空" : "\(cuid.count) 位")"
        summary += "；\(keychainState)"
        return summary
    }

    /// This app is signed ad-hoc for TrollStore and its entitlements carry no
    /// `application-identifier`, which is what iOS uses to place a process in a
    /// keychain access group. Without it every `SecItem*` call fails with
    /// `errSecMissingEntitlement` (-34018). 百度's SDK persists its auth and
    /// device state through the keychain, so a broken keychain is a credible
    /// cause of an auth round that starts and then never reports a verdict.
    static var keychainState: String {
        let service = "com.personal.mocklocation.keychain-probe"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "probe"
        ]

        SecItemDelete(query as CFDictionary)
        var insertion = query
        insertion[kSecValueData as String] = Data("probe".utf8)
        let status = SecItemAdd(insertion as CFDictionary, nil)
        SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess:
            return "钥匙串可用"
        case errSecMissingEntitlement:
            return "钥匙串不可用（-34018 缺少 application-identifier）"
        default:
            return "钥匙串写入失败（OSStatus \(status)）"
        }
    }

    /// Independent reachability check against 百度's SDK auth host. The SDK's
    /// own request is opaque, so this answers the one question its silence
    /// leaves open: can this process talk to that host at all? A 4xx reply
    /// still proves connectivity — only a transport error rules it out.
    static func probeNetwork(completion: @escaping (String) -> Void) {
        guard let url = URL(string: "https://api.map.baidu.com/sdkcs/verify") else {
            completion("无法构造探测请求。")
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "GET"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        URLSession(configuration: configuration).dataTask(with: request) { data, response, error in
            let message: String
            if let error = error as NSError? {
                message = "无法连接 api.map.baidu.com（\(error.domain) \(error.code)）：\(error.localizedDescription)"
            } else if let response = response as? HTTPURLResponse {
                message = "已连通 api.map.baidu.com（HTTP \(response.statusCode)，返回 \(data?.count ?? 0) 字节）。"
            } else {
                message = "请求完成但没有 HTTP 响应。"
            }
            DispatchQueue.main.async { completion(message) }
        }.resume()
    }

    static func configure() {
        let apiKey = storedAPIKey
        guard !apiKey.isEmpty, configuredAPIKey != apiKey else { return }
        // The engine only honors the key passed to its first start; a changed
        // key therefore requires an app relaunch (saveAPIKey reports that).
        guard mapManager == nil else { return }

        BMKMapManager.setAgreePrivacy(true)
        // File logging must be on before the engine starts so its data
        // pipeline failures are recorded. The files land under Library/Caches
        // and Settings exposes them through 查看百度地图日志.
        BMKBaseLog.setlogEnable(true, module: BMKMapModuleTile)
        BMKBaseLog.setlogEnable(true, module: BMKMapModuleBasic)
        // Prefer the SDK's own singleton. `BMKMapManager.h` both declares
        // `sharedInstance` and defines a `BMKMapManagerInstance` macro around
        // it, so SDK internals may route through that object; a separately
        // allocated manager could hold a delegate nothing ever consults.
        let manager = BMKMapManager.sharedInstance() ?? BMKMapManager()
        if manager.start(apiKey, generalDelegate: BaiduSDKGeneralDelegate.shared) {
            mapManager = manager
            configuredAPIKey = apiKey
            engineStartedAt = Date()
        }
    }

    /// Tail of the newest SDK log file per module. `BMKBaseLog` names a
    /// directory per module; the newest file inside holds the current run.
    static func recentLogExcerpt(maxBytesPerModule: Int = 24_576) -> String {
        let modules: [(String, BMKMapModule)] = [
            ("瓦片图模块", BMKMapModuleTile),
            ("基础地图模块", BMKMapModuleBasic)
        ]
        let fileManager = FileManager.default
        var sections: [String] = []

        for (name, module) in modules {
            let directory = BMKBaseLog.getLogFilePath(withModule: module) ?? ""
            guard !directory.isEmpty else {
                sections.append("【\(name)】未返回日志目录。")
                continue
            }
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory), !entries.isEmpty else {
                sections.append("【\(name)】日志目录为空：\(directory)")
                continue
            }

            let newest = entries
                .map { (directory as NSString).appendingPathComponent($0) }
                .compactMap { path -> (String, Date)? in
                    guard let date = (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date else {
                        return nil
                    }
                    return (path, date)
                }
                .max { $0.1 < $1.1 }

            guard let newest, let data = fileManager.contents(atPath: newest.0) else {
                sections.append("【\(name)】无法读取日志文件：\(directory)")
                continue
            }
            let tail = data.suffix(maxBytesPerModule)
            let text = String(data: tail, encoding: .utf8)
                ?? String(decoding: tail, as: UTF8.self)
            sections.append("【\(name)】\(newest.0)\n\(text)")
        }

        return sections.joined(separator: "\n\n====================\n\n")
    }

    /// `start` reported the auth request as sent, but the verdict callback can
    /// go missing entirely (observed on-device). When a started engine has
    /// produced no verdict for `authVerdictTimeout`, tear it down and start a
    /// fresh auth round. Returns true when a restart was performed.
    @discardableResult
    static func restartIfAuthStalled() -> Bool {
        guard let manager = mapManager,
              let startedAt = engineStartedAt,
              !BaiduSDKGeneralDelegate.shared.didReceivePermissionVerdict,
              Date().timeIntervalSince(startedAt) > authVerdictTimeout else {
            return false
        }

        manager.stop()
        BaiduSDKGeneralDelegate.shared.resetForRestart()
        if manager.start(storedAPIKey, generalDelegate: BaiduSDKGeneralDelegate.shared) {
            engineStartedAt = Date()
            return true
        }
        // The failed restart left the engine stopped; drop it so the next
        // configure() builds a fresh one instead of assuming a live engine.
        mapManager = nil
        configuredAPIKey = nil
        engineStartedAt = nil
        return false
    }

    @discardableResult
    static func saveAPIKey(_ value: String) -> Bool {
        let apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let requiresRestart = configuredAPIKey != nil && configuredAPIKey != apiKey

        if apiKey.isEmpty {
            UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        } else {
            UserDefaults.standard.set(apiKey, forKey: apiKeyDefaultsKey)
        }
        return requiresRestart
    }

    private static var apiKey: String {
        (UserDefaults.standard.string(forKey: apiKeyDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

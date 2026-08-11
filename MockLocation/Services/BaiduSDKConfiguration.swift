import Foundation

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
/// likely cover these, but a selector mismatch would silently drop the
/// callbacks; the annotation removes that failure mode outright.
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

    /// Shown only inside map failure banners.
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
        }
        return summary
    }

    static func configure() {
        let apiKey = storedAPIKey
        guard !apiKey.isEmpty, configuredAPIKey != apiKey else { return }
        // The engine only honors the key passed to its first start; a changed
        // key therefore requires an app relaunch (saveAPIKey reports that).
        guard mapManager == nil else { return }

        BMKMapManager.setAgreePrivacy(true)
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

import AMapFoundationKit
import Foundation

enum AMapSDKConfiguration {
    static let apiKeyDefaultsKey = "amap-sdk-api-key"
    /// When false the 高德 tab renders through the key-free raster tile
    /// pipeline instead of the native 3D SDK.
    static let useNativeSDKDefaultsKey = "amap-use-native-sdk"
    /// Selects the native SDK's renderer. Mirrors `AMapMetalEnabledDefaultsKey`
    /// in AMapMapViewFactory.m. Absent means Metal.
    static let metalEnabledDefaultsKey = "amap-metal-enabled"

    private static var configuredAPIKey: String?

    static var isConfigured: Bool { !storedAPIKey.isEmpty }
    /// True when the key was assigned to `AMapServices`. This is a local
    /// property comparison only; it does not mean 高德 accepted the key. The
    /// SDK validates it over the network on first use.
    static var isApplied: Bool {
        !storedAPIKey.isEmpty && AMapServices.shared()?.apiKey == storedAPIKey
    }
    static var storedAPIKey: String { apiKey }

    static var diagnosticSummary: String {
        let key = storedAPIKey
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let keySuffix = key.isEmpty ? "-" : String(key.suffix(4))
        let keyState = isApplied ? "已写入 SDK" : "未写入"
        let resourceVersion = AMapMapViewFactory.resourceBundleVersion() ?? "未识别"
        let renderer = AMapMapViewFactory.isMetalPreferred() ? "Metal" : "GLES"
        let metalState = AMapMapViewFactory.isMetalAvailable() ? "可用" : "不可用"
        return "Bundle ID \(bundleID)；Key \(key.count) 位 / 末四位 \(keySuffix) / \(keyState)；3D 资源 \(resourceVersion)；渲染器 \(renderer)；Metal 设备 \(metalState)"
    }

    static func configure() {
        let apiKey = storedAPIKey
        guard !apiKey.isEmpty,
              let services = AMapServices.shared() else { return }
        services.enableHTTPS = true
        services.securityAgree = true
        services.analysisAgree = true
        services.apiKey = apiKey
        configuredAPIKey = services.apiKey == apiKey ? apiKey : nil
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

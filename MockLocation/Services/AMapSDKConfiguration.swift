import AMapFoundationKit
import Foundation

enum AMapSDKConfiguration {
    static let apiKeyDefaultsKey = "amap-sdk-api-key"

    private static var configuredAPIKey: String?

    static var isConfigured: Bool { !storedAPIKey.isEmpty }
    static var isApplied: Bool {
        !storedAPIKey.isEmpty && AMapServices.shared()?.apiKey == storedAPIKey
    }
    static var storedAPIKey: String { apiKey }

    static var diagnosticSummary: String {
        let key = storedAPIKey
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let keySuffix = key.isEmpty ? "-" : String(key.suffix(4))
        let keyState = isApplied ? "已应用" : "未应用"
        let resourceVersion = AMapMapViewFactory.resourceBundleVersion() ?? "未识别"
        return "Bundle ID \(bundleID)；Key \(key.count) 位 / 末四位 \(keySuffix) / \(keyState)；3D 资源 \(resourceVersion)"
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

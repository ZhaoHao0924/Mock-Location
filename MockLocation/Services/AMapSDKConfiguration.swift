import AMapFoundationKit
import Foundation

enum AMapSDKConfiguration {
    static let apiKeyDefaultsKey = "amap-sdk-api-key"

    private static var configuredAPIKey: String?

    static var isConfigured: Bool { !storedAPIKey.isEmpty }
    static var storedAPIKey: String { apiKey }

    static func configure() {
        let apiKey = storedAPIKey
        guard !apiKey.isEmpty, configuredAPIKey != apiKey,
              let services = AMapServices.shared() else { return }
        services.enableHTTPS = true
        services.apiKey = apiKey
        configuredAPIKey = apiKey
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

import AMapFoundationKit
import Foundation

enum AMapSDKConfiguration {
    static var isConfigured: Bool { !apiKey.isEmpty }

    static func configure() {
        guard isConfigured, let services = AMapServices.shared() else { return }
        services.enableHTTPS = true
        services.analysisAgree = false
        services.apiKey = apiKey
    }

    private static var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "AMapAPIKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

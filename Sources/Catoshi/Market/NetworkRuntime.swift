import Foundation

/// Shared URLSession configuration rules for Catoshi's public, credential-free APIs.
/// Each service still owns its session so socket and REST lifetimes remain independent,
/// but they no longer retain browser-style caches/cookies or use inconsistent timeouts.
enum CatoshiNetworkRuntime {
    static func ephemeralConfiguration(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        waitsForConnectivity: Bool = true
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = waitsForConnectivity
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Catoshi/\(AppMetadata.version) macOS"
        ]
        return configuration
    }
    /// Long-lived public WebSockets must not inherit a short REST resource timeout.
    /// `timeoutIntervalForResource` can otherwise become an accidental lifetime cap on
    /// an always-on stream on some URLSession implementations.
    static func publicWebSocketConfiguration() -> URLSessionConfiguration {
        ephemeralConfiguration(
            requestTimeout: 20,
            resourceTimeout: 7 * 24 * 60 * 60,
            waitsForConnectivity: true
        )
    }

}

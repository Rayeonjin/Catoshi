import Foundation

enum AppMetadata {
    static let fallbackVersion = "2.16.5"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }
}

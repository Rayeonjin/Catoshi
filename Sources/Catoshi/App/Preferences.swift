import Foundation

enum AppPreferenceKey: String {
    case showMenuBarBinance
    case showMenuBarUpbit
    case showMenuBarPremium
    case showMenuBarBinanceSparkline
    case showMenuBarUpbitSparkline
    case showMenuBarPremiumSparkline
    case showMenuBarBinance24h
    case showMenuBarUpbit24h
    case showMenuBarPremium24h
    case displayPalette
    case appLanguage
    case appAppearance
    case catoshiCoat
    case showCatoshi
    case catoshiAnimationEnabled
    case catoshiRandomLifeEnabled
    case catoshiMarketReactionsEnabled
    case catoshiActivity
    case catoshiSensitivity
    case catoshiCooldown
    case catoshiDropReactionEnabled
}

struct PreferenceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func bool(_ key: AppPreferenceKey, default defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key.rawValue) != nil else { return defaultValue }
        return defaults.bool(forKey: key.rawValue)
    }

    func stringEnum<T: RawRepresentable>(_ key: AppPreferenceKey, default defaultValue: T) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key.rawValue), let value = T(rawValue: raw) else {
            return defaultValue
        }
        return value
    }

    func intEnum<T: RawRepresentable>(_ key: AppPreferenceKey, default defaultValue: T) -> T where T.RawValue == Int {
        guard defaults.object(forKey: key.rawValue) != nil,
              let value = T(rawValue: defaults.integer(forKey: key.rawValue)) else {
            return defaultValue
        }
        return value
    }

    func set(_ value: Bool, for key: AppPreferenceKey) {
        defaults.set(value, forKey: key.rawValue)
    }

    func set(_ value: String, for key: AppPreferenceKey) {
        defaults.set(value, forKey: key.rawValue)
    }

    func set(_ value: Int, for key: AppPreferenceKey) {
        defaults.set(value, forKey: key.rawValue)
    }
}

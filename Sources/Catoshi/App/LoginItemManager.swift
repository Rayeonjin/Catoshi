import AppKit
import Combine
import Darwin
import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var legacyLaunchAgentPresent: Bool
    @Published private(set) var isChanging = false
    @Published private(set) var lastErrorMessage: String?

    private static let legacyLaunchAgentName = "com.local.Catoshi.plist"
    private let service = SMAppService.mainApp

    init() {
        status = SMAppService.mainApp.status
        legacyLaunchAgentPresent = Self.legacyLaunchAgentExists
    }

    var isEnabled: Bool {
        status == .enabled || legacyLaunchAgentPresent
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = service.status
        legacyLaunchAgentPresent = Self.legacyLaunchAgentExists
        if status == .enabled && legacyLaunchAgentPresent {
            Self.removeLegacyLaunchAgent()
            legacyLaunchAgentPresent = Self.legacyLaunchAgentExists
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard !isChanging else { return }
        isChanging = true
        lastErrorMessage = nil
        defer {
            refresh()
            isChanging = false
        }

        if enabled {
            enableNativeLoginItem()
        } else {
            disableAllLoginItems()
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func performStartupMigration() {
        guard legacyLaunchAgentExists else { return }

        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            removeLegacyLaunchAgent()
        case .requiresApproval:
            // Keep the working legacy LaunchAgent until the native login item is
            // actually approved. This avoids silently losing auto-start during migration.
            break
        case .notRegistered, .notFound:
            do {
                try service.register()
                if service.status == .enabled {
                    removeLegacyLaunchAgent()
                }
            } catch {
                // Preserve the working legacy LaunchAgent if native migration fails.
                // The Guide tab can surface and retry the native registration later.
                NSLog("Catoshi login-item migration deferred: %@", error.localizedDescription)
            }
        @unknown default:
            break
        }
    }

    static func unregisterForUninstall() {
        let service = SMAppService.mainApp
        if service.status == .enabled || service.status == .requiresApproval {
            try? service.unregister()
        }
        removeLegacyLaunchAgent()
    }

    private func enableNativeLoginItem() {
        switch service.status {
        case .enabled:
            if legacyLaunchAgentPresent {
                Self.removeLegacyLaunchAgent()
            }

        case .requiresApproval:
            // Re-registering an already registered service returns an error. The user
            // must restore approval in System Settings instead.
            openLoginItemsSettings()

        case .notRegistered, .notFound:
            do {
                try service.register()
                let newStatus = service.status
                if newStatus == .enabled {
                    Self.removeLegacyLaunchAgent()
                }
            } catch {
                let newStatus = service.status
                if newStatus == .requiresApproval {
                    openLoginItemsSettings()
                } else if newStatus != .enabled {
                    lastErrorMessage = error.localizedDescription
                }
            }

        @unknown default:
            lastErrorMessage = "Unsupported login-item status."
        }
    }

    private func disableAllLoginItems() {
        switch service.status {
        case .enabled, .requiresApproval:
            do {
                try service.unregister()
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        case .notRegistered:
            break
        case .notFound:
            if !legacyLaunchAgentPresent {
                lastErrorMessage = "macOS could not find the Catoshi login item."
            }
        @unknown default:
            lastErrorMessage = "Unsupported login-item status."
        }

        // A user explicitly choosing OFF should also disable the pre-v2.13.21
        // LaunchAgent if one survived migration.
        Self.removeLegacyLaunchAgent()
    }

    private static var legacyLaunchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(legacyLaunchAgentName, isDirectory: false)
    }

    private static var legacyLaunchAgentExists: Bool {
        FileManager.default.fileExists(atPath: legacyLaunchAgentURL.path)
    }

    private static func removeLegacyLaunchAgent() {
        let url = legacyLaunchAgentURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // The plist may exist without being loaded. Removal below is still valid.
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            NSLog("Catoshi could not remove legacy LaunchAgent: %@", error.localizedDescription)
        }
    }
}

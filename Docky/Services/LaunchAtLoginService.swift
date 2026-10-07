//
//  LaunchAtLoginService.swift
//  Docky
//

import Foundation
import ServiceManagement

final class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notFound, .notRegistered:
            return false
        @unknown default:
            return false
        }
    }

    @discardableResult
    func setEnabled(_ requested: Bool) -> Bool {
        // Personal fork: a Debug build runs from Xcode's build folder, and
        // a login item pointing there would relaunch a stale copy at every
        // login. Debug builds therefore always stay unregistered (and undo
        // any earlier registration); only a Release build honors the
        // "Open at Login" setting.
        #if DEBUG
        let enabled = false
        _ = requested
        #else
        let enabled = requested
        #endif

        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }

            return true
        } catch {
            NSLog("[Docky] Failed to update login item registration: \(error.localizedDescription)")
            return false
        }
    }

    private init() {}
}

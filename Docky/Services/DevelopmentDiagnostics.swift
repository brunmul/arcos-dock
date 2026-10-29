//
//  DevelopmentDiagnostics.swift
//  Docky
//
//  Debug builds only. Writes a few facts about the running build to a text
//  file at the root of the source checkout: how it is signed and whether
//  macOS currently trusts it for accessibility.
//
//  Permissions are granted to a code signature, not to a name. A locally
//  built app that changes signature on every build silently loses them,
//  and the only symptom is a feature that stays off. This file makes that
//  state readable without a debugger.
//

#if DEBUG

import AppKit
import ApplicationServices
import Foundation
import Security

enum DevelopmentDiagnostics {
    /// `<checkout>/.docky-dev-state.txt`, found from this file's own path
    /// at compile time.
    private static let stateFileURL: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // Docky
            .deletingLastPathComponent() // checkout
            .appendingPathComponent(".docky-dev-state.txt")
    }()

    static func writeState(reason: String) {
        let lines = [
            "written: \(Date().formatted(date: .numeric, time: .standard)) (\(reason))",
            "pid: \(ProcessInfo.processInfo.processIdentifier)",
            "bundle: \(Bundle.main.bundlePath)",
            "bundle identifier: \(Bundle.main.bundleIdentifier ?? "none")",
            "designated requirement: \(designatedRequirement())",
            "accessibility trusted: \(AXIsProcessTrusted() ? "yes" : "no")",
            // Permissions don't follow an identifier change.
            "note: since 2026-10-29 the app is com.brunomuller.Oriel (Oriel.app), no longer gt.quintero.Docky (Docky.app). Accessibility, Calendar, Reminders, Automation, Location and Screen Recording must be granted again to Oriel; the old entries for Docky can be removed in System Settings."
        ]
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: stateFileURL, atomically: true, encoding: .utf8)
    }

    /// The requirement macOS records when a permission is granted to this
    /// app, as text. Stable across builds only if it names no code hash.
    private static func designatedRequirement() -> String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return "unavailable (no code object)"
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return "unavailable (no static code)"
        }

        var requirement: SecRequirement?
        let status = SecCodeCopyDesignatedRequirement(staticCode, [], &requirement)
        guard status == errSecSuccess, let requirement else {
            return "unavailable (status \(status))"
        }

        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else {
            return "unavailable (not printable)"
        }
        return text as String
    }
}

#endif

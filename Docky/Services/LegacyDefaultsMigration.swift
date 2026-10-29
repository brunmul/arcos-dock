//
//  LegacyDefaultsMigration.swift
//  Docky
//
//  The app was built as gt.quintero.Docky until it became Oriel, under its
//  own identifier. UserDefaults live in a domain named after the bundle
//  identifier, so the first launch under the new one would start blank.
//  This copies the old domain over once, before anything reads its
//  preferences. The old domain is left as it was.
//
//  Application Support needs nothing: its folder is named "Docky", not
//  after the identifier, and keeps its name.
//

import Foundation

enum LegacyDefaultsMigration {
    static let legacyDomain = "gt.quintero.Docky"
    private static let doneKey = "oriel.copiedLegacyDefaults"

    /// Copies every key of the old domain that the current domain doesn't
    /// have yet. Runs once; does nothing when the app still carries the old
    /// identifier.
    static func runIfNeeded() {
        guard let domain = Bundle.main.bundleIdentifier, domain != legacyDomain else {
            return
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else {
            return
        }

        let legacyApp = legacyDomain as CFString
        let legacy = CFPreferencesCopyMultiple(
            nil,
            legacyApp,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String: Any] ?? [:]

        let current = defaults.persistentDomain(forName: domain) ?? [:]
        var copied = 0
        for (key, value) in legacy where current[key] == nil {
            defaults.set(value, forKey: key)
            copied += 1
        }

        defaults.set(true, forKey: doneKey)
        NSLog("[Oriel] copied %d of %d preferences from %@", copied, legacy.count, legacyDomain)
    }
}

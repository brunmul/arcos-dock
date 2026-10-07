//
//  AppIconCustomizationService.swift
//  Docky
//
//  One-step custom app icons, reachable straight from the dock instead of
//  the Settings > App Icons list:
//
//    - right-click an app > "Change Icon..." / "Reset Icon"
//    - hold Option and drop an image file on an app tile
//
//  The chosen image is copied into
//  ~/Library/Application Support/Docky/Icons/ before it is stored as the
//  app's override, so the icon keeps working after the original file is
//  moved, renamed, or cleaned out of Downloads. The override itself lives
//  in `DockyPreferences.appIconOverrides`, the same place the settings
//  pane writes to, so both entry points stay in sync.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

final class AppIconCustomizationService {
    static let shared = AppIconCustomizationService()

    private let fileManager = FileManager.default

    private init() {}

    func hasCustomIcon(forBundleIdentifier bundleIdentifier: String) -> Bool {
        DockyPreferences.shared.appIconOverride(forBundleIdentifier: bundleIdentifier) != nil
    }

    /// Asks for an image and applies it as the app's icon.
    func chooseIcon(forBundleIdentifier bundleIdentifier: String, appName: String) {
        // One runloop turn later, so the context menu that triggered this
        // has finished closing before a modal panel takes over.
        DispatchQueue.main.async { [self] in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.message = "Choose an image to use as the \(appName) icon."
            panel.prompt = "Use as Icon"
            // The dock floats above standard windows; without the raised
            // level the picker would open underneath it.
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)

            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            setIcon(from: url, forBundleIdentifier: bundleIdentifier)
        }
    }

    /// Copies `sourceURL` into Docky's icon folder and makes it the app's
    /// icon. Returns `false`, leaving any current icon untouched, when the
    /// file is not a readable image or the copy fails.
    @discardableResult
    func setIcon(from sourceURL: URL, forBundleIdentifier bundleIdentifier: String) -> Bool {
        guard !bundleIdentifier.isEmpty, Self.isUsableImage(at: sourceURL) else {
            return false
        }

        let preferences = DockyPreferences.shared
        let previous = preferences.appIconOverride(forBundleIdentifier: bundleIdentifier)

        do {
            try fileManager.createDirectory(at: Self.iconsDirectoryURL, withIntermediateDirectories: true)
            let destination = Self.managedIconURL(forBundleIdentifier: bundleIdentifier, sourceURL: sourceURL)
            try fileManager.copyItem(at: sourceURL, to: destination)

            preferences.setAppIconOverride(
                bundleIdentifier: bundleIdentifier,
                iconPath: destination.path,
                paddingFraction: previous?.paddingFraction
            )
            removeManagedCopy(atPath: previous?.iconPath)
            return true
        } catch {
            NSLog("[Docky] custom icon: could not store %@: %@", sourceURL.path, error.localizedDescription)
            return false
        }
    }

    /// Puts the app back on its own icon (or the active theme's).
    func resetIcon(forBundleIdentifier bundleIdentifier: String) {
        let preferences = DockyPreferences.shared
        let previous = preferences.appIconOverride(forBundleIdentifier: bundleIdentifier)
        preferences.removeAppIconOverride(bundleIdentifier: bundleIdentifier)
        removeManagedCopy(atPath: previous?.iconPath)
    }

    /// Whether a drop of `urls` can become an app icon: exactly one file,
    /// and it is an image.
    static func iconCandidate(in urls: [URL]) -> URL? {
        guard urls.count == 1, let url = urls.first, isUsableImage(at: url) else {
            return nil
        }
        return url
    }

    private static func isUsableImage(at url: URL) -> Bool {
        guard url.isFileURL,
              let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image) else {
            return false
        }
        return NSImage(contentsOf: url) != nil
    }

    /// Deletes a previous icon copy, but only when it is one this service
    /// made. Overrides picked in Settings point at the user's own file and
    /// must never be removed from here.
    private func removeManagedCopy(atPath path: String?) {
        guard let path, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.deletingLastPathComponent().path == Self.iconsDirectoryURL.standardizedFileURL.path else {
            return
        }
        try? fileManager.removeItem(at: url)
    }

    private static var iconsDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return base
            .appending(path: "Docky", directoryHint: .isDirectory)
            .appending(path: "Icons", directoryHint: .isDirectory)
    }

    /// A fresh file name per pick. `IconCacheService` caches decoded images
    /// by path, so reusing one path would keep showing the old icon.
    private static func managedIconURL(forBundleIdentifier bundleIdentifier: String, sourceURL: URL) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let safeIdentifier = String(bundleIdentifier.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        })
        let suffix = UUID().uuidString.prefix(8)
        let fileExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
        return iconsDirectoryURL.appending(
            path: "\(safeIdentifier)-\(suffix).\(fileExtension)",
            directoryHint: .notDirectory
        )
    }
}

/// "Change Icon..." (and "Reset Icon" when one is set) for an app's context
/// menu. Shared by dock tiles and the apps inside an app folder.
func customIconContextActions(for app: AppTile) -> [ContextAction] {
    guard !app.bundleIdentifier.isEmpty else {
        return []
    }

    let bundleIdentifier = app.bundleIdentifier
    let appName = app.displayName
    var actions: [ContextAction] = [
        .action(String(localized: "Change Icon..."), image: contextMenuSymbol("photo")) {
            AppIconCustomizationService.shared.chooseIcon(
                forBundleIdentifier: bundleIdentifier,
                appName: appName
            )
        }
    ]

    if AppIconCustomizationService.shared.hasCustomIcon(forBundleIdentifier: bundleIdentifier) {
        actions.append(.action(
            String(localized: "Reset Icon"),
            image: contextMenuSymbol("arrow.uturn.backward")
        ) {
            AppIconCustomizationService.shared.resetIcon(forBundleIdentifier: bundleIdentifier)
        })
    }

    return actions
}

/// Places the custom-icon actions right after the "Options" submenu of an
/// app menu, or at the end when the menu has none.
func injectingCustomIconActions(into actions: [ContextAction], for app: AppTile) -> [ContextAction] {
    let iconActions = customIconContextActions(for: app)
    guard !iconActions.isEmpty else {
        return actions
    }

    var result = actions
    if let optionsIndex = result.firstIndex(where: { $0.kind == .submenu && $0.title == "Options" }) {
        result.insert(contentsOf: iconActions, at: optionsIndex + 1)
        return result
    }

    if !result.isEmpty, result.last?.kind != .divider {
        result.append(.divider)
    }
    result.append(contentsOf: iconActions)
    return result
}

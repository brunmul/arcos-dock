//
//  SidebarPreferences.swift
//  Docky
//
//  State for the sidebar presentation: an Arc-style column on the left
//  edge that replaces the dock strip. Pinned apps sit in a grid of tiles
//  at the top, pinned folders and open apps are rows that unfold, and
//  widgets stack at the bottom. It also has a compact, icon-only form.
//  See `SidebarWindowController` for the panel and `SidebarView` for its
//  content.
//

import AppKit
import Combine
import Foundation

final class SidebarPreferences: ObservableObject {
    static let shared = SidebarPreferences()

    /// Width of the full sidebar.
    static let fullWidth: CGFloat = 200
    /// Width of the compact sidebar, the icon-only rail.
    static let railWidth: CGFloat = 52
    /// Radius of the concave corners drawn where the sidebar meets the
    /// rest of the screen.
    static let cornerRadius: CGFloat = 12

    /// Whether Docky shows the sidebar instead of the dock strip. Change it
    /// through `SidebarWindowController.setSidebarMode(_:)`, which also
    /// swaps the two windows.
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// Pinned: always on screen. Unpinned: hidden until the pointer reaches
    /// the left edge, like Arc's collapsed sidebar.
    @Published var isPinned: Bool {
        didSet { defaults.set(isPinned, forKey: Keys.isPinned) }
    }

    /// Compact: an icon-only rail, like the collapsed vertical tabs of
    /// Chrome or Brave. Off: the full sidebar with names and widgets.
    @Published var isCompact: Bool {
        didSet { defaults.set(isCompact, forKey: Keys.isCompact) }
    }

    /// Width of the panel in the current mode.
    var panelWidth: CGFloat {
        isCompact ? Self.railWidth : Self.fullWidth
    }

    /// Bundle identifiers of the open apps whose window list is unfolded.
    @Published var expandedAppIdentifiers: Set<String> {
        didSet { defaults.set(Array(expandedAppIdentifiers), forKey: Keys.expandedApps) }
    }

    /// The pinned folder whose contents are listed under the tiles, if
    /// any (`SidebarPinnedFolder.id`). One at a time.
    @Published var openFolderIdentifier: String? {
        didSet { defaults.set(openFolderIdentifier, forKey: Keys.openFolder) }
    }

    /// The widget unfolded to its detailed view. One at a time, so the
    /// widgets never push the app list off the panel; kept as a set for
    /// the stored format.
    @Published var expandedWidgetIdentifiers: Set<String> {
        didSet { defaults.set(Array(expandedWidgetIdentifiers), forKey: Keys.expandedWidgets) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isEnabled = "docky.fork.sidebar.isEnabled"
        static let isPinned = "docky.fork.sidebar.isPinned"
        static let isCompact = "docky.fork.sidebar.isCompact"
        static let expandedApps = "docky.fork.sidebar.expandedApps"
        static let openFolder = "docky.fork.sidebar.openFolder"
        static let expandedWidgets = "docky.fork.sidebar.expandedWidgets"
    }

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        isPinned = defaults.object(forKey: Keys.isPinned) as? Bool ?? true
        isCompact = defaults.bool(forKey: Keys.isCompact)
        expandedAppIdentifiers = Set(defaults.stringArray(forKey: Keys.expandedApps) ?? [])
        openFolderIdentifier = defaults.string(forKey: Keys.openFolder)
        expandedWidgetIdentifiers = Set(defaults.stringArray(forKey: Keys.expandedWidgets) ?? [])
    }

    func toggleExpansion(ofApp bundleIdentifier: String) {
        if expandedAppIdentifiers.contains(bundleIdentifier) {
            expandedAppIdentifiers.remove(bundleIdentifier)
        } else {
            expandedAppIdentifiers.insert(bundleIdentifier)
        }
    }

    func toggleFolder(_ identifier: String) {
        openFolderIdentifier = openFolderIdentifier == identifier ? nil : identifier
    }

    func toggleWidget(_ identifier: String) {
        if expandedWidgetIdentifiers.contains(identifier) {
            expandedWidgetIdentifiers = []
        } else {
            expandedWidgetIdentifiers = [identifier]
        }
    }
}

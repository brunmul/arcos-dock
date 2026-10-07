//
//  SidebarPreferences.swift
//  Docky
//
//  State for the sidebar presentation: an Arc-style column on the left
//  edge that replaces the dock strip. Favorites sit in a grid at the top,
//  open apps are listed as rows that unfold into their windows, and
//  widgets take the full width at the bottom. See `SidebarWindowController`
//  for the panel and `SidebarView` for its content.
//

import AppKit
import Combine
import Foundation

final class SidebarPreferences: ObservableObject {
    static let shared = SidebarPreferences()

    /// Width of the panel's content, without the gap to the screen edge.
    static let panelWidth: CGFloat = 248
    /// Gap between the panel and the screen edges it floats next to.
    static let screenMargin: CGFloat = 6

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

    /// Bundle identifiers of the open apps whose window list is unfolded.
    @Published var expandedAppIdentifiers: Set<String> {
        didSet { defaults.set(Array(expandedAppIdentifiers), forKey: Keys.expandedApps) }
    }

    /// App folders that are folded shut; folders start open.
    @Published var collapsedFolderIdentifiers: Set<String> {
        didSet { defaults.set(Array(collapsedFolderIdentifiers), forKey: Keys.collapsedFolders) }
    }

    /// Widgets unfolded to their detailed view.
    @Published var expandedWidgetIdentifiers: Set<String> {
        didSet { defaults.set(Array(expandedWidgetIdentifiers), forKey: Keys.expandedWidgets) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isEnabled = "docky.fork.sidebar.isEnabled"
        static let isPinned = "docky.fork.sidebar.isPinned"
        static let expandedApps = "docky.fork.sidebar.expandedApps"
        static let collapsedFolders = "docky.fork.sidebar.collapsedFolders"
        static let expandedWidgets = "docky.fork.sidebar.expandedWidgets"
    }

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        isPinned = defaults.object(forKey: Keys.isPinned) as? Bool ?? true
        expandedAppIdentifiers = Set(defaults.stringArray(forKey: Keys.expandedApps) ?? [])
        collapsedFolderIdentifiers = Set(defaults.stringArray(forKey: Keys.collapsedFolders) ?? [])
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
        if collapsedFolderIdentifiers.contains(identifier) {
            collapsedFolderIdentifiers.remove(identifier)
        } else {
            collapsedFolderIdentifiers.insert(identifier)
        }
    }

    func toggleWidget(_ identifier: String) {
        if expandedWidgetIdentifiers.contains(identifier) {
            expandedWidgetIdentifiers.remove(identifier)
        } else {
            expandedWidgetIdentifiers.insert(identifier)
        }
    }
}

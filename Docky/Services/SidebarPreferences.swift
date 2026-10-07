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

    /// The icon chosen for each pinned folder, by `SidebarPinnedFolder.id`.
    /// A folder without an entry gets a default; see `glyph(forFolder:named:)`.
    @Published var folderGlyphs: [String: SidebarFolderGlyph] {
        didSet {
            if let data = try? JSONEncoder().encode(folderGlyphs) {
                defaults.set(data, forKey: Keys.folderGlyphs)
            }
        }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isEnabled = "docky.fork.sidebar.isEnabled"
        static let isPinned = "docky.fork.sidebar.isPinned"
        static let isCompact = "docky.fork.sidebar.isCompact"
        static let expandedApps = "docky.fork.sidebar.expandedApps"
        static let openFolder = "docky.fork.sidebar.openFolder"
        static let folderGlyphs = "docky.fork.sidebar.folderGlyphs"
    }

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        isPinned = defaults.object(forKey: Keys.isPinned) as? Bool ?? true
        isCompact = defaults.bool(forKey: Keys.isCompact)
        expandedAppIdentifiers = Set(defaults.stringArray(forKey: Keys.expandedApps) ?? [])
        openFolderIdentifier = defaults.string(forKey: Keys.openFolder)
        if let data = defaults.data(forKey: Keys.folderGlyphs),
           let stored = try? JSONDecoder().decode([String: SidebarFolderGlyph].self, from: data) {
            folderGlyphs = stored
        } else {
            folderGlyphs = [:]
        }
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

    // MARK: - Folder icons

    /// The folder's icon: the one the user picked, otherwise one guessed
    /// from its name, otherwise a plain folder.
    func glyph(forFolder identifier: String, named name: String) -> SidebarFolderGlyph {
        folderGlyphs[identifier] ?? SidebarFolderGlyph.suggested(forName: name)
    }

    func setGlyphSymbol(_ symbol: String, forFolder identifier: String, named name: String) {
        var glyph = glyph(forFolder: identifier, named: name)
        glyph.symbol = symbol
        folderGlyphs[identifier] = glyph
    }

    func setGlyphColor(_ color: SidebarFolderGlyph.Tint, forFolder identifier: String, named name: String) {
        var glyph = glyph(forFolder: identifier, named: name)
        glyph.tint = color
        folderGlyphs[identifier] = glyph
    }
}

/// A pinned folder's icon in the sidebar: one symbol in one color, picked
/// from a short list the way a project's icon is picked in Claude.
struct SidebarFolderGlyph: Codable, Equatable {
    var symbol: String
    var tint: Tint

    enum Tint: String, Codable, CaseIterable, Identifiable {
        case gray, blue, purple, pink, red, orange, yellow, green, teal

        var id: String { rawValue }

        var title: String {
            rawValue.capitalized
        }

        var nsColor: NSColor {
            switch self {
            case .gray: .secondaryLabelColor
            case .blue: .systemBlue
            case .purple: .systemPurple
            case .pink: .systemPink
            case .red: .systemRed
            case .orange: .systemOrange
            case .yellow: .systemYellow
            case .green: .systemGreen
            case .teal: .systemTeal
            }
        }
    }

    /// The symbols offered in the folder's menu, with the name shown there.
    static let choices: [(symbol: String, title: String)] = [
        ("folder.fill", "Folder"),
        ("square.grid.2x2.fill", "Apps"),
        ("wrench.and.screwdriver.fill", "Tools"),
        ("sparkles", "Sparkles"),
        ("bubble.left.and.bubble.right.fill", "Chat"),
        ("play.rectangle.fill", "Media"),
        ("music.note", "Music"),
        ("photo.fill", "Photos"),
        ("paintbrush.fill", "Design"),
        ("pencil", "Writing"),
        ("doc.fill", "Documents"),
        ("book.fill", "Reading"),
        ("terminal.fill", "Code"),
        ("chart.bar.fill", "Data"),
        ("briefcase.fill", "Work"),
        ("desktopcomputer", "Desktop"),
        ("arrow.down.circle.fill", "Downloads"),
        ("globe", "Web"),
        ("cart.fill", "Shopping"),
        ("gamecontroller.fill", "Games"),
        ("house.fill", "Home"),
        ("heart.fill", "Favorites"),
        ("star.fill", "Star"),
        ("bolt.fill", "Bolt"),
        ("lock.fill", "Private")
    ]

    /// A starting icon guessed from the folder's name (English and French),
    /// so a fresh sidebar is not a row of identical folders.
    static func suggested(forName name: String) -> SidebarFolderGlyph {
        let lowered = name.lowercased()
        let rules: [(keywords: [String], symbol: String, tint: Tint)] = [
            (["util", "outil", "tool", "system", "système"], "wrench.and.screwdriver.fill", .gray),
            (["media", "média", "video", "vidéo", "film"], "play.rectangle.fill", .red),
            (["ai", "ia", "intelligence"], "sparkles", .orange),
            (["com", "chat", "message", "social", "mail"], "bubble.left.and.bubble.right.fill", .green),
            (["bureau", "desktop"], "desktopcomputer", .blue),
            (["app"], "square.grid.2x2.fill", .blue),
            (["download", "télécharg", "telecharg"], "arrow.down.circle.fill", .blue),
            (["doc"], "doc.fill", .blue),
            (["music", "musique", "audio"], "music.note", .pink),
            (["photo", "image", "picture"], "photo.fill", .teal),
            (["design", "créa", "crea"], "paintbrush.fill", .purple),
            (["dev", "code"], "terminal.fill", .gray),
            (["game", "jeu"], "gamecontroller.fill", .purple),
            (["work", "travail", "pro"], "briefcase.fill", .orange)
        ]

        for rule in rules {
            // "ai" and "ia" only as the whole name: they hide in too many
            // other words ("mail", "media") to match as a fragment.
            let matches = rule.keywords.contains { keyword in
                keyword.count <= 2 ? lowered == keyword : lowered.contains(keyword)
            }
            if matches {
                return SidebarFolderGlyph(symbol: rule.symbol, tint: rule.tint)
            }
        }
        return SidebarFolderGlyph(symbol: "folder.fill", tint: .gray)
    }
}

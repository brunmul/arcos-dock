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

    /// Draws app icons as one-color glyphs without their plate, instead
    /// of the full-color icons.
    @Published var usesTintedIcons: Bool {
        didSet { defaults.set(usesTintedIcons, forKey: Keys.usesTintedIcons) }
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
        static let usesTintedIcons = "docky.fork.sidebar.usesTintedIcons"
        static let expandedApps = "docky.fork.sidebar.expandedApps"
        static let openFolder = "docky.fork.sidebar.openFolder"
        static let folderGlyphs = "docky.fork.sidebar.folderGlyphs"
    }

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        isPinned = defaults.object(forKey: Keys.isPinned) as? Bool ?? true
        isCompact = defaults.bool(forKey: Keys.isCompact)
        usesTintedIcons = defaults.object(forKey: Keys.usesTintedIcons) as? Bool ?? true
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

/// A pinned folder's icon in the sidebar, in the manner of a project's icon
/// in Claude: a line-drawn symbol on a soft wash of its own color.
struct SidebarFolderGlyph: Codable, Equatable {
    var symbol: String
    var tint: Tint

    enum Tint: String, Codable, CaseIterable, Identifiable {
        case gray, blue, purple, pink, red, orange, yellow, green, teal

        var id: String { rawValue }

        var title: String {
            rawValue.capitalized
        }

        /// Muted, earthy inks rather than the system's signal colors: the
        /// tiles sit next to app icons all day and should not shout. Each
        /// is a little lighter on a dark sidebar so the line stays legible.
        var nsColor: NSColor {
            let (red, green, blue) = components
            let light = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
            let dark = light.blended(withFraction: 0.42, of: .white) ?? light
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            }
        }

        private var components: (CGFloat, CGFloat, CGFloat) {
            switch self {
            case .gray: (0.42, 0.42, 0.44)
            case .blue: (0.29, 0.41, 0.55)
            case .purple: (0.47, 0.34, 0.58)
            case .pink: (0.68, 0.29, 0.44)
            case .red: (0.62, 0.30, 0.25)
            case .orange: (0.66, 0.40, 0.24)
            case .yellow: (0.58, 0.45, 0.20)
            case .green: (0.36, 0.48, 0.28)
            case .teal: (0.24, 0.48, 0.47)
            }
        }
    }

    /// The symbol in its line-drawn form. Icons saved before the folders
    /// took this style were filled ones; they map to the same symbol.
    var outlineSymbol: String {
        Self.outline(symbol)
    }

    static func outline(_ symbol: String) -> String {
        symbol.hasSuffix(".fill") ? String(symbol.dropLast(5)) : symbol
    }

    /// The symbols offered in the folder's menu, with the name shown there.
    /// Every one is drawn in outline only, with no filled part, so the set
    /// reads as one family at a light weight.
    static let choices: [(symbol: String, title: String)] = [
        ("folder", "Folder"),
        ("square.grid.2x2", "Apps"),
        ("wrench.and.screwdriver", "Tools"),
        ("wand.and.rays", "Magic"),
        ("lightbulb", "Ideas"),
        ("bubble.left.and.bubble.right", "Chat"),
        ("paperplane", "Send"),
        ("film", "Video"),
        ("headphones", "Audio"),
        ("camera", "Camera"),
        ("photo", "Photos"),
        ("paintpalette", "Design"),
        ("pencil", "Writing"),
        ("doc.text", "Documents"),
        ("book", "Reading"),
        ("chevron.left.forwardslash.chevron.right", "Code"),
        ("terminal", "Terminal"),
        ("flask", "Lab"),
        ("chart.bar", "Data"),
        ("briefcase", "Work"),
        ("calendar", "Calendar"),
        ("clock", "Time"),
        ("display", "Desktop"),
        ("tray.and.arrow.down", "Downloads"),
        ("globe", "Web"),
        ("cart", "Shopping"),
        ("gamecontroller", "Games"),
        ("house", "Home"),
        ("heart", "Favorites"),
        ("star", "Star"),
        ("bookmark", "Bookmark"),
        ("lock", "Private")
    ]

    /// A starting icon guessed from the folder's name (English and French),
    /// so a fresh sidebar is not a row of identical folders.
    static func suggested(forName name: String) -> SidebarFolderGlyph {
        let lowered = name.lowercased()
        let rules: [(keywords: [String], symbol: String, tint: Tint)] = [
            (["util", "outil", "tool", "system", "système"], "wrench.and.screwdriver", .gray),
            (["media", "média", "video", "vidéo", "film"], "film", .red),
            (["ai", "ia", "intelligence"], "wand.and.rays", .orange),
            (["com", "chat", "message", "social", "mail"], "bubble.left.and.bubble.right", .teal),
            (["bureau", "desktop"], "display", .blue),
            (["app"], "square.grid.2x2", .purple),
            (["download", "télécharg", "telecharg"], "tray.and.arrow.down", .yellow),
            (["doc"], "doc.text", .blue),
            (["music", "musique", "audio"], "headphones", .pink),
            (["photo", "image", "picture"], "photo", .teal),
            (["design", "créa", "crea"], "paintpalette", .red),
            (["dev", "code"], "chevron.left.forwardslash.chevron.right", .pink),
            (["game", "jeu"], "gamecontroller", .purple),
            (["work", "travail", "pro"], "briefcase", .orange)
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
        return SidebarFolderGlyph(symbol: "folder", tint: .gray)
    }
}

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

    /// Width of the full sidebar until it is resized, and the range it
    /// can be dragged across.
    static let defaultFullWidth: CGFloat = 200
    static let fullWidthRange: ClosedRange<CGFloat> = 180...420
    /// Width of the compact sidebar, the icon-only rail.
    static let railWidth: CGFloat = 52
    /// Height of the bar along the bottom of the screen, in both forms.
    static let bottomHeight: CGFloat = 46
    /// Radius of the concave corners drawn where the sidebar meets the
    /// rest of the screen.
    static let cornerRadius: CGFloat = 16

    /// Whether Docky shows the sidebar instead of the dock strip. Change it
    /// through `SidebarWindowController.setSidebarMode(_:)`, which also
    /// swaps the two windows.
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// Where the bar sits: down the left edge (the sidebar) or along the
    /// bottom of the screen, where it lays the same content out in a row.
    @Published var edge: SidebarEdge {
        didSet { defaults.set(edge.rawValue, forKey: Keys.edge) }
    }

    var isBottom: Bool { edge == .bottom }

    /// The bar's colors (`SidebarTheme`): "claude" for the warm paper and
    /// charcoal that follow the system, or one of the Slack-like themes.
    @Published var themeID: String {
        didSet { defaults.set(themeID, forKey: Keys.themeID) }
    }

    /// Sets the desktop picture to the theme's colors, so the menu bar and
    /// the desktop around the windows match the bar (`SidebarWallpaper`).
    @Published var matchesWallpaper: Bool {
        didSet { defaults.set(matchesWallpaper, forKey: Keys.matchesWallpaper) }
    }

    var theme: SidebarTheme {
        SidebarTheme.all.first { $0.id == themeID } ?? .claude
    }

    /// Parts left out of the bar along the bottom and of the compact rail,
    /// where room is short. The full sidebar always shows everything.
    @Published var hiddenSections: Set<SidebarSection> {
        didSet { defaults.set(hiddenSections.map(\.rawValue), forKey: Keys.hiddenSections) }
    }

    /// Down the left side: the open apps and tabs come up in a panel when
    /// the pointer reaches the bottom of the screen, to switch between them.
    @Published var showsBottomSwitcher: Bool {
        didSet { defaults.set(showsBottomSwitcher, forKey: Keys.showsBottomSwitcher) }
    }

    /// Widgets unticked in "…" → Widgets, by their identifier.
    @Published var hiddenWidgetIDs: Set<String> {
        didSet { defaults.set(Array(hiddenWidgetIDs), forKey: Keys.hiddenWidgetIDs) }
    }

    func shows(widget: WidgetTile) -> Bool {
        !hiddenWidgetIDs.contains(widget.identifier)
    }

    func setShows(widget: WidgetTile, _ shows: Bool) {
        if shows {
            hiddenWidgetIDs.remove(widget.identifier)
        } else {
            hiddenWidgetIDs.insert(widget.identifier)
        }
    }

    // MARK: Top and bottom

    /// Pinned apps and sites set at the bottom, with the widgets, by
    /// `SidebarPinnedItem.id`. The others sit at the top.
    @Published var bottomItemIDs: Set<String> {
        didSet { defaults.set(Array(bottomItemIDs), forKey: Keys.bottomItemIDs) }
    }

    /// Widgets set at the top, with the pinned apps, by identifier. The
    /// others sit at the bottom.
    @Published var topWidgetIDs: Set<String> {
        didSet { defaults.set(Array(topWidgetIDs), forKey: Keys.topWidgetIDs) }
    }

    /// How each place draws what it holds: tiles at the top, rows at the
    /// bottom, until changed in "…" → Layout.
    @Published var topLayout: SidebarLayout {
        didSet { defaults.set(topLayout.rawValue, forKey: Keys.topLayout) }
    }

    @Published var bottomLayout: SidebarLayout {
        didSet { defaults.set(bottomLayout.rawValue, forKey: Keys.bottomLayout) }
    }

    func place(ofItem id: String) -> SidebarPlace {
        bottomItemIDs.contains(id) ? .bottom : .top
    }

    func move(item id: String, to place: SidebarPlace) {
        if place == .bottom {
            bottomItemIDs.insert(id)
        } else {
            bottomItemIDs.remove(id)
        }
    }

    func place(of widget: WidgetTile) -> SidebarPlace {
        topWidgetIDs.contains(widget.identifier) ? .top : .bottom
    }

    func move(_ widget: WidgetTile, to place: SidebarPlace) {
        if place == .top {
            topWidgetIDs.insert(widget.identifier)
        } else {
            topWidgetIDs.remove(widget.identifier)
        }
    }

    /// Every widget the bar can show: the dock's, but the bare date.
    static func allWidgets(in store: TileStore) -> [WidgetTile] {
        store.tiles.compactMap { tile in
            if case .widget(let widget) = tile.content, widget.kind != .calendarDate {
                return widget
            }
            return nil
        }
    }

    func shows(_ section: SidebarSection) -> Bool {
        !hiddenSections.contains(section)
    }

    func setShows(_ section: SidebarSection, _ shows: Bool) {
        if shows {
            hiddenSections.remove(section)
        } else {
            hiddenSections.insert(section)
        }
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

    /// Shows the icon an app's website uses in a browser tab, when one
    /// can be found, in place of the app's own icon (`SidebarFaviconStore`).
    @Published var usesWebsiteIcons: Bool {
        didSet { defaults.set(usesWebsiteIcons, forKey: Keys.usesWebsiteIcons) }
    }

    /// Lists the pinned apps that are open in the Apps group as well, and
    /// not only as tiles at the top.
    @Published var showsPinnedAppsInOpenList: Bool {
        didSet { defaults.set(showsPinnedAppsInOpenList, forKey: Keys.showsPinnedAppsInOpenList) }
    }

    /// Shows the Trash tile among the folders. The dock always keeps a
    /// Trash, so this is the sidebar's own choice.
    @Published var showsTrash: Bool {
        didSet { defaults.set(showsTrash, forKey: Keys.showsTrash) }
    }

    /// Width of the full sidebar, set by dragging its right edge.
    @Published var fullWidth: CGFloat {
        didSet { defaults.set(Double(fullWidth), forKey: Keys.fullWidth) }
    }

    /// Width of the panel in the current mode.
    var panelWidth: CGFloat {
        isCompact ? Self.railWidth : fullWidth
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

    /// Websites pinned among the apps at the top, in pinning order.
    @Published var pinnedSites: [SidebarPinnedSite] {
        didSet {
            if let data = try? JSONEncoder().encode(pinnedSites) {
                defaults.set(data, forKey: Keys.pinnedSites)
            }
        }
    }

    /// The pinned site a page belongs to, if any.
    func pinnedSite(for pageURL: URL?) -> SidebarPinnedSite? {
        pinnedSites.first { $0.matches(pageURL) }
    }

    /// Pins the page itself: a root page pins the whole site, a deeper one
    /// (an artifact, a project) just that page and what is under it.
    func pin(site url: URL, title: String) {
        guard SidebarPinnedSite.host(of: url) != nil, pinnedSite(for: url) == nil else { return }
        pinnedSites.append(SidebarPinnedSite(url: url, title: title))
    }

    func unpin(_ site: SidebarPinnedSite) {
        pinnedSites.removeAll { $0.id == site.id }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let fullWidth = "docky.fork.sidebar.fullWidth"
        static let bottomItemIDs = "docky.fork.sidebar.bottomItems"
        static let topWidgetIDs = "docky.fork.sidebar.topWidgets"
        static let topLayout = "docky.fork.sidebar.topLayout"
        static let bottomLayout = "docky.fork.sidebar.bottomLayout"
        static let pinnedSites = "docky.fork.sidebar.pinnedSites"
        static let edge = "docky.fork.sidebar.edge"
        static let themeID = "docky.fork.sidebar.theme"
        static let matchesWallpaper = "docky.fork.sidebar.matchesWallpaper"
        static let hiddenSections = "docky.fork.sidebar.hiddenSections"
        static let isEnabled = "docky.fork.sidebar.isEnabled"
        static let isPinned = "docky.fork.sidebar.isPinned"
        static let isCompact = "docky.fork.sidebar.isCompact"
        static let usesTintedIcons = "docky.fork.sidebar.usesTintedIcons"
        static let usesWebsiteIcons = "docky.fork.sidebar.usesWebsiteIcons"
        static let showsPinnedAppsInOpenList = "docky.fork.sidebar.showsPinnedAppsInOpenList"
        static let showsTrash = "docky.fork.sidebar.showsTrash"
        static let hiddenWidgetIDs = "docky.fork.sidebar.hiddenWidgets"
        static let showsBottomSwitcher = "docky.fork.sidebar.showsBottomSwitcher"
        static let expandedApps = "docky.fork.sidebar.expandedApps"
        static let openFolder = "docky.fork.sidebar.openFolder"
        static let folderGlyphs = "docky.fork.sidebar.folderGlyphs"
    }

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        edge = defaults.string(forKey: Keys.edge).flatMap(SidebarEdge.init(rawValue:)) ?? .left
        themeID = defaults.string(forKey: Keys.themeID) ?? SidebarTheme.claude.id
        matchesWallpaper = defaults.object(forKey: Keys.matchesWallpaper) as? Bool ?? true
        hiddenSections = Set((defaults.stringArray(forKey: Keys.hiddenSections) ?? []).compactMap(SidebarSection.init(rawValue:)))
        isPinned = defaults.object(forKey: Keys.isPinned) as? Bool ?? true
        isCompact = defaults.bool(forKey: Keys.isCompact)
        let storedWidth = (defaults.object(forKey: Keys.fullWidth) as? Double).map { CGFloat($0) }
        fullWidth = min(max(storedWidth ?? Self.defaultFullWidth, Self.fullWidthRange.lowerBound), Self.fullWidthRange.upperBound)
        usesTintedIcons = defaults.object(forKey: Keys.usesTintedIcons) as? Bool ?? true
        usesWebsiteIcons = defaults.object(forKey: Keys.usesWebsiteIcons) as? Bool ?? true
        showsPinnedAppsInOpenList = defaults.object(forKey: Keys.showsPinnedAppsInOpenList) as? Bool ?? true
        showsTrash = defaults.object(forKey: Keys.showsTrash) as? Bool ?? true
        hiddenWidgetIDs = Set(defaults.stringArray(forKey: Keys.hiddenWidgetIDs) ?? [])
        bottomItemIDs = Set(defaults.stringArray(forKey: Keys.bottomItemIDs) ?? [])
        topWidgetIDs = Set(defaults.stringArray(forKey: Keys.topWidgetIDs) ?? [])
        topLayout = defaults.string(forKey: Keys.topLayout).flatMap(SidebarLayout.init(rawValue:)) ?? .grid
        bottomLayout = defaults.string(forKey: Keys.bottomLayout).flatMap(SidebarLayout.init(rawValue:)) ?? .list
        showsBottomSwitcher = defaults.object(forKey: Keys.showsBottomSwitcher) as? Bool ?? true
        expandedAppIdentifiers = Set(defaults.stringArray(forKey: Keys.expandedApps) ?? [])
        openFolderIdentifier = defaults.string(forKey: Keys.openFolder)
        if let data = defaults.data(forKey: Keys.pinnedSites),
           let stored = try? JSONDecoder().decode([SidebarPinnedSite].self, from: data) {
            pinnedSites = stored
        } else {
            pinnedSites = []
        }
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

enum SidebarEdge: String, CaseIterable {
    case left
    case bottom
}

/// A color theme for the bar, in the manner of Slack's: a light gradient
/// from the top color to the bottom one, with light text on the dark ones.
/// The colors come from Slack's theme swatches, the dark ones deepened for
/// a sidebar. "Claude" is the bar's own warm paper and charcoal, which
/// follow the system's light or dark mode.
struct SidebarTheme: Identifiable, Equatable {
    let id: String
    let name: String
    /// sRGB, as 0xRRGGBB.
    let top: Int
    let bottom: Int
    let isDark: Bool

    var isClaude: Bool { id == Self.claude.id }

    static let claude = SidebarTheme(id: "claude", name: "Claude", top: 0xF5F4ED, bottom: 0xF5F4ED, isDark: false)

    static let all: [SidebarTheme] = [
        claude,
        SidebarTheme(id: "kind-of-blue", name: "Kind of Blue", top: 0x96C4EC, bottom: 0x4676A1, isDark: false),
        SidebarTheme(id: "funky-fresh", name: "Funky Fresh", top: 0xC4BEF7, bottom: 0x82C8AC, isDark: false),
        SidebarTheme(id: "jazz-club", name: "Jazz Club", top: 0x701B1A, bottom: 0x331134, isDark: true),
        SidebarTheme(id: "electric-fusion", name: "Electric Fusion", top: 0xE0F1A3, bottom: 0xB6F9B2, isDark: false),
        SidebarTheme(id: "brassy", name: "Brassy", top: 0xEBD47B, bottom: 0xC2A94F, isDark: false),
        SidebarTheme(id: "sunglasses-inside", name: "Sunglasses Inside", top: 0x2F1236, bottom: 0x220926, isDark: true),
        SidebarTheme(id: "aubergine", name: "Aubergine", top: 0x391742, bottom: 0x29092E, isDark: true),
        SidebarTheme(id: "clementine", name: "Clementine", top: 0x833B17, bottom: 0x7F3612, isDark: true),
        SidebarTheme(id: "banana", name: "Banana", top: 0xFDF5C5, bottom: 0xF8D854, isDark: false),
        SidebarTheme(id: "jade", name: "Jade", top: 0x2C5B42, bottom: 0x26513E, isDark: true),
        SidebarTheme(id: "lagoon", name: "Lagoon", top: 0x204868, bottom: 0x1E344B, isDark: true),
        SidebarTheme(id: "barbra", name: "Barbra", top: 0xF6CEDE, bottom: 0xEE88AB, isDark: false),
        SidebarTheme(id: "gray", name: "Gray", top: 0xECECEC, bottom: 0xCBCCCF, isDark: false),
        SidebarTheme(id: "mood-indigo", name: "Mood Indigo", top: 0x17215A, bottom: 0x0A154C, isDark: true),
        SidebarTheme(id: "tritanopia", name: "Tritanopia", top: 0x2F2F2F, bottom: 0x000000, isDark: true),
        SidebarTheme(id: "protanopia", name: "Protanopia", top: 0x423247, bottom: 0x210429, isDark: true),
        SidebarTheme(id: "raspberry-beret", name: "Raspberry Beret", top: 0xF1DEFB, bottom: 0xEE87AA, isDark: false),
        SidebarTheme(id: "big-business", name: "Big Business", top: 0x3C3C3F, bottom: 0x1D2A6E, isDark: true),
        SidebarTheme(id: "pog", name: "POG", top: 0xF2D9E4, bottom: 0xE2B447, isDark: false),
        SidebarTheme(id: "mint-chip", name: "Mint Chip", top: 0xD1EDBB, bottom: 0x8499E6, isDark: false),
        SidebarTheme(id: "pbandj", name: "PB&J", top: 0xE4D5C2, bottom: 0xD69BB8, isDark: false),
        SidebarTheme(id: "chill-vibes", name: "Chill Vibes", top: 0x2D5C43, bottom: 0x214752, isDark: true),
        SidebarTheme(id: "forest-floor", name: "Forest Floor", top: 0x445719, bottom: 0x4D3618, isDark: true),
        SidebarTheme(id: "slackr", name: "Slackr", top: 0xF6CFE0, bottom: 0x6AC3ED, isDark: false),
        SidebarTheme(id: "sea-glass", name: "Sea Glass", top: 0xC4EEF1, bottom: 0xD4A5F0, isDark: false),
        SidebarTheme(id: "lemon-lime", name: "Lemon Lime", top: 0x7C621B, bottom: 0x26500F, isDark: true),
        SidebarTheme(id: "falling-leaves", name: "Falling Leaves", top: 0x553C20, bottom: 0x6A5416, isDark: true),
        SidebarTheme(id: "sunrise", name: "Sunrise", top: 0xFBE8DD, bottom: 0xF1A9C3, isDark: false),
        SidebarTheme(id: "choco-mint", name: "Choco Mint", top: 0x493219, bottom: 0x204233, isDark: true),
        SidebarTheme(id: "cmyk", name: "CMYK", top: 0xBCEBFC, bottom: 0xEB8BAE, isDark: false),
        SidebarTheme(id: "haberdashery", name: "Haberdashery", top: 0x19354F, bottom: 0x3A2E0B, isDark: true),
        SidebarTheme(id: "hoth", name: "Hoth", top: 0xF9F9F9, bottom: 0xB3E8FB, isDark: false),
        SidebarTheme(id: "ochin", name: "Ochin", top: 0x1F4167, bottom: 0x16305B, isDark: true),
        SidebarTheme(id: "sweet-treat", name: "Sweet Treat", top: 0xF9DDDC, bottom: 0xF0A298, isDark: false),
    ]
}

/// The parts of the bar that can be left out where room is short.
enum SidebarSection: String, CaseIterable {
    case pinned
    case folders
    case openApps
    case tabs
    case widgets

    var title: String {
        switch self {
        case .pinned: "Pinned Apps & Sites"
        case .folders: "Folders & Trash"
        case .openApps: "Open Apps"
        case .tabs: "Browser Tabs"
        case .widgets: "Widgets"
        }
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

/// A website pinned to the sidebar: the address it opens and the name it
/// shows in its tooltip. It stands for its whole site: any open tab on the
/// same host counts as it.
struct SidebarPinnedSite: Codable, Equatable, Identifiable {
    let url: URL
    let title: String

    var id: String { url.absoluteString }

    var host: String? { Self.host(of: url) }

    /// True for a page of this pinned site. A site pinned at its root
    /// (gmail.com) takes any page on its host; one pinned deeper, like a
    /// Claude artifact, only the pages under its own address, so pinning
    /// one artifact does not claim every page of claude.ai.
    func matches(_ pageURL: URL?) -> Bool {
        guard let pageURL, let host, Self.host(of: pageURL) == host else { return false }
        let path = url.path
        guard !path.isEmpty, path != "/" else { return true }
        return pageURL.path.hasPrefix(path)
    }

    /// The host without "www.", the way tabs are matched to sites.
    static func host(of url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// The two places pinned apps, sites and widgets can sit: under the
/// greeting, or at the foot of the sidebar.
enum SidebarPlace: String {
    case top, bottom

    var other: SidebarPlace { self == .top ? .bottom : .top }

    /// The menu item that sends an item to the other place.
    var moveTitle: String { self == .top ? "Move to Top" : "Move to Bottom" }
}

/// Tiles across, the way the pinned apps have always been shown, or one
/// row each, the way the widgets have.
enum SidebarLayout: String, CaseIterable {
    case grid, list

    var title: String { self == .grid ? "Grid" : "List" }
}

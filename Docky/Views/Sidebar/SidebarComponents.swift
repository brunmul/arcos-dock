//
//  SidebarComponents.swift
//  Docky
//
//  The rows and tiles the sidebar is built from: the tiles of the pinned
//  apps and folders, the list a folder opens into, the open apps that
//  unfold into their windows, and the small controls they share. Layout and data wiring live
//  in `SidebarView`.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Metrics and shared pieces

/// One set of sizes for every row, so the list reads as a single column:
/// a 16pt icon, a 13pt label, 28pt tall, like a browser's vertical tabs.
enum SidebarMetrics {
    static let rowHeight: CGFloat = 28
    static let rowIconSize: CGFloat = 16
    static let rowFontSize: CGFloat = 13
    static let rowSpacing: CGFloat = 8
    static let rowPadding: CGFloat = 8
    /// Where a nested row's content starts: under its parent's label.
    static let nestedIndent: CGFloat = rowPadding + rowIconSize + rowSpacing
    static let tileHeight: CGFloat = 34
    static let tileIconSize: CGFloat = 20
    static let tileCornerRadius: CGFloat = 9
    static let tileSpacing: CGFloat = 5
    /// As many tiles across as the sidebar's width holds, for the pinned
    /// apps and the pinned folders: four at the default width, more as
    /// the sidebar is widened.
    static let tileColumns = [
        GridItem(.adaptive(minimum: 38), spacing: tileSpacing)
    ]
    static let foldAnimation = Animation.spring(response: 0.28, dampingFraction: 0.86)
}

/// An app's icon, from the first of these that applies:
///
///   0. the Claude icon chosen for it in its menu (`SidebarItemIcon`);
///   1. the custom icon pack (`SidebarIconPack`), for the apps it covers;
///   2. with website icons on, the icon of the app's website when one
///      was found (`SidebarFaviconStore`);
///   3. the icon picked with "Change Icon...", or the app's own, without
///      the shadow and margin macOS draws around it (`SidebarIconTrim`).
struct SidebarAppIcon: View {
    let bundleIdentifier: String
    let size: CGFloat

    @Bindable private var preferences = DockyPreferences.shared
    @ObservedObject private var iconPack = SidebarIconPack.shared
    @ObservedObject private var favicons = SidebarFaviconStore.shared
    @ObservedObject private var sidebar = SidebarPreferences.shared
    @ObservedObject private var icons = IconCacheService.shared

    private static let ink = Color.primary.opacity(0.74)

    var body: some View {
        if let custom = sidebar.wornIcon(forItem: "app-\(bundleIdentifier)") {
            SidebarItemIconView(icon: custom, size: size)
        } else if let packIcon = iconPack.icon(forBundleIdentifier: bundleIdentifier) {
            SidebarPackIconView(icon: packIcon, ink: Self.ink)
                .frame(width: size, height: size)
        } else if sidebar.usesWebsiteIcons, let favicon = favicons.icon(forBundleIdentifier: bundleIdentifier) {
            SidebarPackIconView(icon: favicon, ink: faviconInk(for: favicon))
                .frame(width: size, height: size)
        } else {
            Image(nsImage: SidebarIconTrim.trimmed(image, key: glyphKey))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }

    /// A one-color website icon takes the main color of the app's own
    /// icon (Spotify green, WhatsApp green), as the cut-out glyphs do.
    private func faviconInk(for favicon: SidebarPackIcon) -> Color {
        guard favicon.isGlyph, sidebar.usesTintedIcons,
              let tint = SidebarIconGlyph.glyph(for: image, key: glyphKey)?.tint
        else { return Self.ink }
        return Color(nsColor: tint)
    }

    private var overrideURL: URL? {
        preferences.effectiveAppIconOverrideURL(forBundleIdentifier: bundleIdentifier)
    }

    private var image: NSImage {
        if let overrideURL, let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }
        return IconCacheService.shared.icon(forBundleIdentifier: bundleIdentifier)
    }

    /// A custom icon gets its own glyph, apart from the app's stock one.
    private var glyphKey: String {
        if let overrideURL {
            return "\(bundleIdentifier)|\(overrideURL.path)"
        }
        return bundleIdentifier
    }
}

/// A system symbol drawn like a Claude project icon: the mark in a color
/// on a rounded wash of the same color. Stands in for a site with no icon.
struct SidebarAppSymbolView: View {
    let systemName: String
    let tint: Color
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.56, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.24 : 0.15))
            )
    }
}

/// An icon from the custom pack: a glyph takes the given ink, a colored
/// icon is drawn as it is.
struct SidebarPackIconView: View {
    let icon: SidebarPackIcon
    let ink: Color

    var body: some View {
        if icon.isGlyph {
            Image(nsImage: icon.image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(ink)
        } else {
            Image(nsImage: icon.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        }
    }
}

/// The same right-click menu an app gets in the dock strip: its windows,
/// the Dock's own entries, then "Change Icon...".
func sidebarAppContextActions(
    for app: AppTile,
    modifierFlags: NSEvent.ModifierFlags
) -> [ContextAction] {
    guard !app.bundleIdentifier.isEmpty else { return [] }

    // The dock's own tile when the app is pinned: the menu reads "pinned"
    // from the tile's id, and a made-up tile would offer to pin it again.
    let tile = TileStore.shared.tiles.first { tile in
        guard tile.id.hasPrefix("pinned:"), case .app(let pinned) = tile.content else { return false }
        return pinned.bundleIdentifier == app.bundleIdentifier
    } ?? Tile(content: .app(app))
    let baseActions = MenuCatalogService.shared
        .contextActions(for: tile, modifierFlags: modifierFlags) ?? []
    let windows = WorkspaceService.shared.appWindows(bundleIdentifier: app.bundleIdentifier)
    let withWindows = injectingAppWindowActions(windows, into: baseActions)
    let withIcon = injectingCustomIconActions(into: withWindows, for: app)

    var pinActions = sidebarPinActions(for: app)
    guard !pinActions.isEmpty else { return withIcon }
    if sidebarIsPinned(app.bundleIdentifier) {
        pinActions += sidebarItemIconActions(forItem: SidebarPinnedItem.app(app).id)
    }
    return withIcon.isEmpty ? pinActions : pinActions + [.divider] + withIcon
}

private func sidebarIsPinned(_ bundleIdentifier: String) -> Bool {
    TileStore.shared.tiles.contains { tile in
        guard tile.id.hasPrefix("pinned:"), case .app(let pinned) = tile.content else { return false }
        return pinned.bundleIdentifier == bundleIdentifier
    }
}

/// "Pin to Bottom" for a pinned app or site at the top, "Pin to Top"
/// for one at the bottom.
func sidebarMoveAction(forItem id: String) -> ContextAction {
    let preferences = SidebarPreferences.shared
    let destination = preferences.place(ofItem: id).other
    return .action(destination.moveTitle) {
        preferences.move(item: id, to: destination)
    }
}

/// "Super Pin" for a pinned app or site, ticked while it is one: it then
/// leads its place, stays shown even closed, and is ringed in the theme's
/// accent (Bruno, 28 October, as on Windows).
func sidebarSuperPinAction(forItem id: String) -> ContextAction {
    let preferences = SidebarPreferences.shared
    return .action("Super Pin", isOn: preferences.isSuperPin(id)) {
        let allIDs = SidebarHotKeyService.shared.allPinnedItems.map(\.id)
        withAnimation(SidebarMetrics.foldAnimation) {
            preferences.toggleSuperPin(id, allIDs: allIDs)
        }
    }
}

/// "Icon" for a pinned app or site: an icon from the Notion pack in place
/// of its own, in a color drawn from the theme or chosen by hand;
/// "Default" gives it back its own icon. The ~900 page icons come by first
/// letter, the interface ones apart, so no menu runs off the screen.
func sidebarItemIconActions(forItem id: String) -> [ContextAction] {
    let preferences = SidebarPreferences.shared

    func iconAction(_ name: String) -> ContextAction {
        let worn = preferences.wornIcon(forItem: id)
        return .action(
            NotionIconPack.title(of: name),
            image: NotionIconPack.coloredImage(named: name, tint: worn?.tint, theme: preferences.theme),
            isOn: worn?.name == name
        ) {
            preferences.setIcon(name, forItem: id)
        }
    }

    return [.lazySubmenu("Icon") {
        let current = preferences.wornIcon(forItem: id)
        var actions: [ContextAction] = []
        // The worn icon's color first (Bruno, 27 October): Auto, the color
        // the theme gives it, or one of the folders' tints.
        if let current {
            let isDark = NotionIconPack.sidebarIsDark(preferences.theme)
            let auto = NotionIconPack.color(forIcon: current.name, theme: preferences.theme, isDark: isDark)
            actions += [.action("Auto", image: sidebarSwatch(auto), isOn: current.tint == nil) {
                preferences.setIconTint(nil, forItem: id)
            }]
            // The folders' muted tints, then the vivid ones.
            for tint in SidebarIconTint.allCases {
                if tint == .vividRed { actions += [.divider] }
                actions += [.action(tint.title, image: sidebarSwatch(tint.ink(isDark: isDark)), isOn: current.tint == tint) {
                    preferences.setIconTint(tint, forItem: id)
                }]
            }
            actions += [.divider]
        }
        actions += [
            .action("Default", isOn: current == nil) { preferences.setIcon(nil, forItem: id) },
            .divider
        ]
        actions += NotionIconPack.pageNamesByInitial.map { group in
            // The letter holding the current icon shows it, to find it again.
            let holdsCurrent = current.map { group.names.contains($0.name) } ?? false
            return .lazySubmenu(
                group.initial,
                image: holdsCurrent ? current.flatMap {
                    NotionIconPack.coloredImage(named: $0.name, tint: $0.tint, theme: preferences.theme)
                } : nil
            ) { group.names.map(iconAction) }
        }
        if !NotionIconPack.interfaceNames.isEmpty {
            actions += [.divider, .lazySubmenu("Interface") { NotionIconPack.interfaceNames.map(iconAction) }]
        }
        return actions
    }]
}

/// A dot of color for the menus.
private func sidebarSwatch(_ color: NSColor) -> NSImage? {
    NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
}

/// A Notion icon worn by a pinned app or site, in relief as in Bruno's
/// mockup (27 October), like Windows' `NotionIcons.Embossed`: the glyph
/// filled with a vertical gradient from its color lifted 4 %·k toward
/// white at the top to 6 %·k toward black at the bottom (k =
/// `NotionIconPack.reliefStrength`), over a white copy
/// half a point higher (60 % opaque, 21 % on a dark bar), like a stamp lit
/// from above. No drop shadow, no bevel. The color is the one chosen by
/// hand, or drawn from the sidebar's theme; on a tile, the tile itself is
/// its cartouche (`SidebarTintedTileWash`).
struct SidebarItemIconView: View {
    let icon: SidebarItemIcon
    let size: CGFloat

    @ObservedObject private var sidebar = SidebarPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let ink = NotionIconPack.color(forIcon: icon.name, tint: icon.tint, theme: sidebar.theme, isDark: isDark)
        // Softened by k in the light theme only; as first drawn on a dark bar.
        let k = NotionIconPack.reliefStrength(ink)
        let (lift, shade) = isDark ? (0.064, 0.096) : (0.04 * k, 0.06 * k)
        ZStack {
            if let image = NotionIconPack.image(named: icon.name) {
                glyph(image)
                    .foregroundStyle(Color.white)
                    .opacity(isDark ? 0.21 : 0.60)
                    .offset(y: -0.5)
                glyph(image)
                    .foregroundStyle(LinearGradient(
                        colors: [
                            Color(nsColor: NotionIconPack.mix(ink, .white, lift)),
                            Color(nsColor: NotionIconPack.mix(ink, .black, shade))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            }
        }
        .frame(width: size, height: size)
    }

    private func glyph(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }
}

/// A pinned site's menu, on its tile and on its row.
func sidebarSiteContextActions(for site: SidebarPinnedSite) -> [ContextAction] {
    let browserTabs = BrowserTabsService.shared
    let openTabs = (browserTabs.tabs ?? []).filter { site.matches($0.url) }
    var actions: [ContextAction] = [
        .action("Open in New Tab") { browserTabs.open(site.url) },
        .divider,
        .action("Unpin") {
            SidebarPreferences.shared.move(item: SidebarPinnedItem.site(site).id, to: .top)
            SidebarPreferences.shared.superPinIDs.remove(SidebarPinnedItem.site(site).id)
            SidebarPreferences.shared.unpin(site)
        },
        sidebarSuperPinAction(forItem: SidebarPinnedItem.site(site).id),
        sidebarMoveAction(forItem: SidebarPinnedItem.site(site).id)
    ] + sidebarItemIconActions(forItem: SidebarPinnedItem.site(site).id)
    // The site's open tabs close from here, as an app quits from its tile.
    if !openTabs.isEmpty {
        actions += [
            .divider,
            .action(openTabs.count == 1 ? "Close Tab" : "Close \(openTabs.count) Tabs") {
                for tab in openTabs {
                    browserTabs.close(tab)
                }
            }
        ]
    }
    return actions
}

/// "Pin to Top" and "Pin to Bottom" for an app that is not pinned, in one
/// step; "Unpin" and "Pin to" the other place for one that is. None for
/// Finder, which the dock always keeps.
private func sidebarPinActions(for app: AppTile) -> [ContextAction] {
    let bundleIdentifier = app.bundleIdentifier
    guard bundleIdentifier != "com.apple.finder" else { return [] }
    let id = SidebarPinnedItem.app(app).id
    let preferences = SidebarPreferences.shared

    guard sidebarIsPinned(bundleIdentifier) else {
        return [SidebarPlace.top, .bottom].map { place in
            .action(place.pinTitle) {
                preferences.move(item: id, to: place)
                TileStore.shared.setPinnedApp(bundleIdentifier: bundleIdentifier, pinned: true)
            }
        }
    }
    return [
        .action("Unpin") {
            preferences.move(item: id, to: .top)
            preferences.superPinIDs.remove(id)
            TileStore.shared.setPinnedApp(bundleIdentifier: bundleIdentifier, pinned: false)
        },
        sidebarSuperPinAction(forItem: id),
        sidebarMoveAction(forItem: id)
    ]
}

/// Opens the system's app search: the Apps view on recent macOS, Launchpad
/// before it, and Docky's own Launchpad when neither is installed.
func sidebarOpenAppSearch() {
    let candidates = [
        "/System/Applications/Apps.app",
        "/System/Applications/Launchpad.app"
    ]
    for path in candidates where FileManager.default.fileExists(atPath: path) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        return
    }
    LaunchpadOverlayService.shared.present()
}

/// Unread count next to an app, as the Dock reports it.
struct SidebarBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(minWidth: 15, minHeight: 15)
            .background(Capsule().fill(Color.red))
    }
}

extension BrowserTab {
    /// The unread count a site puts in its tab's title, the way Gmail
    /// writes "Inbox (3)" and others "(3) Messages": the first number in
    /// brackets. Four-digit numbers are left alone, they are mostly years.
    var unreadCount: String? {
        guard let match = tab_unreadPattern.firstMatch(
            in: title, range: NSRange(title.startIndex..., in: title)
        ), let range = Range(match.range(at: 1), in: title) else { return nil }
        let count = String(title[range])
        return count == "0" ? nil : count
    }
}

private let tab_unreadPattern = try! NSRegularExpression(pattern: #"\((\d{1,3}\+?)\)"#)

/// Background shared by every row and tile: nothing at rest, a faint wash
/// under the pointer, and a light raised pill for the current item, the
/// way a browser marks the active tab.
struct SidebarItemBackground: View {
    let isHovered: Bool
    let isCurrent: Bool
    var restingOpacity: Double = 0
    var cornerRadius: CGFloat = 7
    /// The Notion icon a pinned item's tile wears: the tile itself becomes
    /// its cartouche, washed with the icon's color (Bruno, 27 October).
    var notionIcon: SidebarItemIcon? = nil
    /// A tile of the pinned grid: a light line around it, in the bar's
    /// text color, so the tiles stand out (Bruno, 27 October).
    var outlined: Bool = false
    /// A super pin: a line of this width in the theme's accent
    /// (`NotionIconPack.superPinAccent`) at 85 %, in place of the fine one,
    /// over a soft inner glow of the accent (`SidebarSuperPinGlow`), over
    /// the active state as well (Bruno, 28 and 29 October; as Windows'
    /// docky-windows fed4595). Nil for any other item.
    var superPinLineWidth: CGFloat? = nil
    /// The super pin's `SidebarPinnedItem.id`: its line and glow take the
    /// item's own color (`SidebarSuperPinColor`, Bruno, 29 October).
    var superPinItemID: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = colorScheme == .dark
        let isSuperPin = superPinLineWidth != nil
        Group {
            // The one in front wears the white pill, Notion icon or not, so
            // the selection reads the same everywhere.
            if let notionIcon, !isCurrent {
                SidebarTintedTileWash(icon: notionIcon, isHovered: isHovered)
                    .clipShape(shape)
            } else if isCurrent {
                // A clearly visible active state (Bruno, 27 October; as
                // Windows' docky-windows 89462ac): solid white on a light
                // bar, 26 % on a dark one, a 1 pt line and a small shadow.
                shape
                    .fill(Color.white.opacity(isDark ? 0.26 : 1))
                    .overlay(
                        shape.strokeBorder(
                            isDark ? Color.white.opacity(0.24) : Color.primary.opacity(0.16),
                            lineWidth: isSuperPin ? 0 : 1
                        )
                    )
                    .shadow(color: .black.opacity(isDark ? 0.35 : 0.14), radius: 3, x: 0, y: 1)
            } else {
                shape.fill(Color.primary.opacity(isHovered ? restingOpacity + 0.06 : restingOpacity))
            }
        }
        .overlay {
            if let superPinLineWidth, let superPinItemID {
                SidebarSuperPinDecoration(
                    itemID: superPinItemID,
                    lineWidth: superPinLineWidth,
                    cornerRadius: cornerRadius,
                    isDark: isDark
                )
            } else if outlined && !isCurrent {
                shape.strokeBorder(Color.primary.opacity(isDark ? 0.10 : 0.08), lineWidth: 1)
            }
        }
    }
}

/// A super pin's inner glow: a radial gradient of the accent fitted to the
/// tile (an ellipse touching the middle of each edge), clear up to 45 %,
/// alpha 0x30 / 0x40 (light / dark bar) at 85 %, 0x55 / 0x70 at the edge,
/// and that last color on into the corners, the densest part. Under the
/// content, never faded with it, and never hit.
struct SidebarSuperPinGlow: View {
    let accent: NSColor
    let isDark: Bool

    var body: some View {
        let color = Color(nsColor: accent)
        let middle = (isDark ? 0x40 : 0x30) / 255.0
        let edge = (isDark ? 0x70 : 0x55) / 255.0
        Canvas { context, size in
            let radiusX = size.width / 2
            let radiusY = size.height / 2
            guard radiusX > 0, radiusY > 0 else { return }
            // A circle of radius X, squashed to the ellipse about the center.
            context.translateBy(x: radiusX, y: radiusY)
            context.scaleBy(x: 1, y: radiusY / radiusX)
            let reach = max(size.width, size.height) * 2
            context.fill(
                Path(CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: color.opacity(0), location: 0),
                        .init(color: color.opacity(0), location: 0.45),
                        .init(color: color.opacity(middle), location: 0.85),
                        .init(color: color.opacity(edge), location: 1)
                    ]),
                    center: .zero,
                    startRadius: 0,
                    endRadius: radiusX
                )
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The tile of a pinned item wearing a Notion icon, as in Bruno's relief
/// mockup (27 October), like Windows' `PinnedArea.Wash`: flat, a radial
/// gradient from the icon's color mixed 18 %·k into the bar at the center to
/// 4 %·k at the edge (k = `NotionIconPack.reliefStrength`, lighter on light
/// colors), over an ellipse 80 % of the width by 100 % of the
/// height; ×1.06 brighter under the pointer. No shadow, line or gloss.
struct SidebarTintedTileWash: View {
    let icon: SidebarItemIcon
    let isHovered: Bool

    @ObservedObject private var sidebar = SidebarPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let ink = NotionIconPack.color(forIcon: icon.name, tint: icon.tint, theme: sidebar.theme, isDark: isDark)
        let bar = NotionIconPack.barColor(theme: sidebar.theme, isDark: isDark)
        let factor = isHovered ? 1.06 : 1
        // Softened on light colors in the light theme (Bruno found 30 % too
        // marked there); as first drawn on a dark bar, "just right" there.
        let k = NotionIconPack.reliefStrength(ink)
        let (inner, outer) = isDark ? (0.30, 0.04) : (0.18 * k, 0.04 * k)
        let center = Color(nsColor: NotionIconPack.brightened(NotionIconPack.mix(bar, ink, inner), by: factor))
        let edge = Color(nsColor: NotionIconPack.brightened(NotionIconPack.mix(bar, ink, outer), by: factor))
        Canvas { context, size in
            let radiusX = size.width * 0.8
            let radiusY = size.height * 1.0
            guard radiusX > 0, radiusY > 0 else { return }
            // A circle of radius X, squashed to the ellipse about the center.
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: 1, y: radiusY / radiusX)
            let reach = max(size.width, size.height) * 2
            context.fill(
                Path(CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)),
                with: .radialGradient(
                    Gradient(colors: [center, edge]),
                    center: .zero,
                    startRadius: 0,
                    endRadius: radiusX
                )
            )
        }
    }
}

// MARK: - Pinned apps

/// A pinned app or a pinned site: they share one list, so the open ones of
/// both kinds can come first together.
enum SidebarPinnedItem: Identifiable {
    case app(AppTile)
    case site(SidebarPinnedSite)

    var id: String {
        switch self {
        case .app(let app): "app-\(app.bundleIdentifier)"
        case .site(let site): "site-\(site.id)"
        }
    }
}

/// What tells a pinned site from a pinned app: a small solid globe, drawn
/// by hand like Windows (DockyWin Marks.cs), at 9 pt in the theme's ink at
/// 60 %. Apps have no mark.
struct SidebarSiteMark: View {
    var body: some View {
        SidebarGlobeMarkShape()
            .fill(Color.primary.opacity(0.6))
            .frame(width: 9, height: 9)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A solid globe on a 16×16 grid: a disc cut by a meridian ring and an
/// equator band.
struct SidebarGlobeMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let disc = Path(ellipseIn: CGRect(x: 0.5, y: 0.5, width: 15, height: 15))
        var ring = Path(ellipseIn: CGRect(x: 8 - 3.7, y: 8 - 8.2, width: 7.4, height: 16.4))
        ring = ring.subtracting(Path(ellipseIn: CGRect(x: 8 - 2.3, y: 8 - 6.8, width: 4.6, height: 13.6)))
        let band = Path(CGRect(x: 0, y: 7.3, width: 16, height: 1.4))
        let globe = disc.subtracting(ring).subtracting(band)
        return globe.applying(CGAffineTransform(scaleX: rect.width / 16, y: rect.height / 16)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

/// A solid screen on its stand, on a 16×16 grid, like Windows (DockyWin
/// Marks.cs). Ready for an "on another screen" mark; none is drawn on the
/// Mac yet.
struct SidebarDisplayMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 2.5, y: 2))
        p.addLine(to: CGPoint(x: 13.5, y: 2))
        p.addArc(tangent1End: CGPoint(x: 15, y: 2), tangent2End: CGPoint(x: 15, y: 3.5), radius: 1.5)
        p.addLine(to: CGPoint(x: 15, y: 10.5))
        p.addArc(tangent1End: CGPoint(x: 15, y: 12), tangent2End: CGPoint(x: 13.5, y: 12), radius: 1.5)
        p.addLine(to: CGPoint(x: 9.5, y: 12))
        p.addLine(to: CGPoint(x: 9.5, y: 13.5))
        p.addLine(to: CGPoint(x: 11, y: 13.5))
        p.addArc(center: CGPoint(x: 11, y: 14), radius: 0.5, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: 5, y: 14.5))
        p.addArc(center: CGPoint(x: 5, y: 14), radius: 0.5, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: 6.5, y: 13.5))
        p.addLine(to: CGPoint(x: 6.5, y: 12))
        p.addLine(to: CGPoint(x: 2.5, y: 12))
        p.addArc(tangent1End: CGPoint(x: 1, y: 12), tangent2End: CGPoint(x: 1, y: 10.5), radius: 1.5)
        p.addLine(to: CGPoint(x: 1, y: 3.5))
        p.addArc(tangent1End: CGPoint(x: 1, y: 2), tangent2End: CGPoint(x: 2.5, y: 2), radius: 1.5)
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 16, y: rect.height / 16)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

/// A pinned app or site as a row, for a place set to List: its icon and
/// its name, like an open app's row.
struct SidebarPinnedItemRow: View {
    let item: SidebarPinnedItem

    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var browserTabs = BrowserTabsService.shared
    @ObservedObject private var sidebar = SidebarPreferences.shared
    @State private var isHovered = false

    private var title: String {
        switch item {
        case .app(let app): app.displayName
        case .site(let site): site.title.isEmpty ? (site.host ?? site.url.absoluteString) : site.title
        }
    }

    private var isOpen: Bool {
        switch item {
        case .app(let app): workspace.isRunning(bundleIdentifier: app.bundleIdentifier)
        case .site(let site): browserTabs.tab(for: site) != nil
        }
    }

    private var isSuperPin: Bool {
        sidebar.isSuperPin(item.id)
    }

    private var isCurrent: Bool {
        switch item {
        case .app(let app):
            return workspace.frontmostBundleIdentifier == app.bundleIdentifier
        case .site(let site):
            guard let tab = browserTabs.tab(for: site) else { return false }
            return workspace.frontmostBundleIdentifier == BrowserTabsService.browserBundleIdentifier
                && tab.isActive && tab.isInFrontWindow
        }
    }

    var body: some View {
        HStack(spacing: SidebarMetrics.rowSpacing) {
            icon
                .frame(width: SidebarMetrics.rowIconSize, height: SidebarMetrics.rowIconSize)

            Text(title)
                .font(.system(size: SidebarMetrics.rowFontSize, weight: isCurrent ? .medium : .regular))
                .foregroundStyle(isOpen ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if case .site = item {
                SidebarSiteMark()
            }
        }
        // A closed super pin stays in its place, faded (Bruno, 28 October).
        .opacity(isSuperPin && !isOpen ? 0.5 : 1)
        .padding(.leading, SidebarMetrics.rowPadding)
        .padding(.trailing, 5)
        .frame(height: SidebarMetrics.rowHeight)
        .background(SidebarItemBackground(
            isHovered: isHovered,
            isCurrent: isCurrent,
            superPinLineWidth: isSuperPin ? 1.25 : nil,
            superPinItemID: item.id
        ))
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .onHover { isHovered = $0 }
        .help(title)
        .overlay {
            SidebarContextMenuArea(
                actionProvider: { flags in
                    switch item {
                    case .app(let app): sidebarAppContextActions(for: app, modifierFlags: flags)
                    case .site(let site): sidebarSiteContextActions(for: site)
                    }
                },
                preferredEdge: .maxX
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { open() }
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .app(let app):
            SidebarAppIcon(bundleIdentifier: app.bundleIdentifier, size: SidebarMetrics.rowIconSize)
        case .site(let site):
            if let custom = SidebarPreferences.shared.wornIcon(forItem: item.id) {
                SidebarItemIconView(icon: custom, size: SidebarMetrics.rowIconSize)
            } else {
                SidebarWebIcon(url: browserTabs.tab(for: site)?.url ?? site.url, size: SidebarMetrics.rowIconSize)
            }
        }
    }

    private func open() {
        switch item {
        case .app(let app): workspace.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        case .site(let site): browserTabs.openOrFocus(site)
        }
    }
}

/// What one place of the sidebar holds, top or bottom: pinned apps and
/// sites, and widgets, drawn as tiles or as rows. Tiles of every kind
/// share one grid; a widget's tile is its icon, with its detail on hover
/// as on its row.
struct SidebarPlaceView: View {
    let items: [SidebarPinnedItem]
    let widgets: [WidgetTile]
    let layout: SidebarLayout
    /// Every pinned item in order, top and bottom, for dragging between
    /// the two places.
    let allItemIDs: [String]

    @ObservedObject private var drag = SidebarPinDrag.shared
    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var browserTabs = BrowserTabsService.shared

    @ObservedObject private var sidebar = SidebarPreferences.shared

    /// The open ones show, and the super pins even closed, first as they
    /// come first in `items`; the others wait behind the overflow item.
    private var openItems: [SidebarPinnedItem] { items.filter { isOpen($0) || sidebar.isSuperPin($0.id) } }
    private var closedItems: [SidebarPinnedItem] { items.filter { !isOpen($0) && !sidebar.isSuperPin($0.id) } }

    private func isOpen(_ item: SidebarPinnedItem) -> Bool {
        switch item {
        case .app(let app): workspace.isRunning(bundleIdentifier: app.bundleIdentifier)
        case .site(let site): browserTabs.tab(for: site) != nil
        }
    }

    var body: some View {
        let closed = closedItems
        switch layout {
        case .grid:
            LazyVGrid(columns: SidebarMetrics.tileColumns, spacing: SidebarMetrics.tileSpacing) {
                ForEach(openItems) { item in
                    draggable(SidebarPinnedItemTile(item: item, dimsClosedSuperPin: true, showsActiveBar: true), item: item)
                }
                if !closed.isEmpty {
                    SidebarPinnedOverflow(items: closed, isRow: false, allItemIDs: allItemIDs)
                }
                ForEach(widgets, id: \.identifier) { widget in
                    SidebarWidgetItem(widget: widget, isRail: true)
                }
            }
        case .list:
            VStack(spacing: 2) {
                ForEach(openItems) { item in
                    draggable(SidebarPinnedItemRow(item: item), item: item)
                }
                if !closed.isEmpty {
                    SidebarPinnedOverflow(items: closed, isRow: true, allItemIDs: allItemIDs)
                }
                ForEach(widgets, id: \.identifier) { widget in
                    SidebarWidgetItem(widget: widget)
                }
            }
        }
    }

    /// Dragged, an item moves live to where the pointer is over another
    /// one, top or bottom; the order stays as it is dropped.
    private func draggable(_ content: some View, item: SidebarPinnedItem) -> some View {
        content
            .opacity(drag.draggedID == item.id ? 0.4 : 1)
            .onDrag {
                drag.begin(item.id)
                return NSItemProvider(object: item.id as NSString)
            }
            .onDrop(of: [.text], delegate: SidebarPinDropDelegate(
                targetID: item.id,
                allItemIDs: allItemIDs,
                drag: drag
            ))
    }
}

/// The pinned items that are not open, behind one tile ("+3") or one row
/// ("3 More") at the end of their place. A click opens a panel beside the
/// sidebar with them as tiles, to launch one; they can be dragged from
/// there back among the others.
struct SidebarPinnedOverflow: View {
    let items: [SidebarPinnedItem]
    let isRow: Bool
    let allItemIDs: [String]

    @State private var isHovered = false
    @State private var isShowingPanel = false

    private static let panelColumns = Array(
        repeating: GridItem(.fixed(44), spacing: SidebarMetrics.tileSpacing),
        count: 5
    )

    var body: some View {
        Button {
            isShowingPanel.toggle()
        } label: {
            label
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Pinned, not open")
        .popover(isPresented: $isShowingPanel, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pinned")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Self.panelColumns, spacing: SidebarMetrics.tileSpacing) {
                    ForEach(items) { item in
                        SidebarPinnedItemTile(item: item)
                            .onDrag {
                                SidebarPinDrag.shared.begin(item.id)
                                return NSItemProvider(object: item.id as NSString)
                            }
                    }
                }
            }
            .padding(12)
            .frame(width: CGFloat(min(items.count, 5)) * (44 + SidebarMetrics.tileSpacing) + 24 - SidebarMetrics.tileSpacing)
            .sidebarThemeScheme(SidebarPreferences.shared.theme)
        }
    }

    @ViewBuilder
    private var label: some View {
        if isRow {
            HStack(spacing: SidebarMetrics.rowSpacing) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: SidebarMetrics.rowIconSize, height: SidebarMetrics.rowIconSize)
                Text("\(items.count) More")
                    .font(.system(size: SidebarMetrics.rowFontSize))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.leading, SidebarMetrics.rowPadding)
            .frame(height: SidebarMetrics.rowHeight)
            .background(SidebarItemBackground(isHovered: isHovered || isShowingPanel, isCurrent: false))
        } else {
            Text("+\(items.count)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: SidebarMetrics.tileHeight)
                .background(SidebarItemBackground(
                    isHovered: isHovered || isShowingPanel,
                    isCurrent: false,
                    restingOpacity: 0.07,
                    cornerRadius: SidebarMetrics.tileCornerRadius,
                    outlined: true
                ))
        }
    }
}

/// The pinned item being dragged, shared by the top and bottom places.
final class SidebarPinDrag: ObservableObject {
    static let shared = SidebarPinDrag()
    @Published var draggedID: String?

    /// A drag let go outside the places gets no drop: the item would stay
    /// dimmed. It is cleared once the mouse button is up.
    func begin(_ id: String) {
        draggedID = id
        watchForRelease()
    }

    private func watchForRelease() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.draggedID != nil else { return }
            if NSEvent.pressedMouseButtons == 0 {
                self.draggedID = nil
            } else {
                self.watchForRelease()
            }
        }
    }
}

private struct SidebarPinDropDelegate: DropDelegate {
    let targetID: String
    let allItemIDs: [String]
    let drag: SidebarPinDrag

    func dropEntered(info: DropInfo) {
        guard let dragged = drag.draggedID, dragged != targetID else { return }
        withAnimation(SidebarMetrics.foldAnimation) {
            SidebarPreferences.shared.movePinned(dragged, onto: targetID, allIDs: allItemIDs)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.draggedID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

struct SidebarPinnedItemTile: View {
    let item: SidebarPinnedItem
    /// In a place of the full sidebar, a closed super pin shows faded.
    var dimsClosedSuperPin = false
    /// In a place of the full sidebar, the one in front has a small bar of
    /// its icon's color at its foot (`SidebarActiveBar`).
    var showsActiveBar = false

    @ObservedObject private var hotKeys = SidebarHotKeyService.shared

    var body: some View {
        tile
            // While ⌃⌥ is held, the number of the shortcut that opens it.
            .overlay(alignment: .bottomTrailing) {
                if hotKeys.showsNumbers, let number = hotKeys.number(for: item) {
                    Text("\(number)")
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(minWidth: 13, minHeight: 13)
                        .background(SidebarPalette.clay, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(2)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var tile: some View {
        switch item {
        case .app(let app): SidebarAppTile(app: app, dimsClosedSuperPin: dimsClosedSuperPin, showsActiveBar: showsActiveBar)
        case .site(let site): SidebarSiteTile(site: site, dimsClosedSuperPin: dimsClosedSuperPin, showsActiveBar: showsActiveBar)
        }
    }
}

/// A pinned website as a tile, beside the pinned apps: the site's icon,
/// the dot under it while a tab on the site is open, and the white pill
/// while that tab is the one in front. A click goes to the open tab, or
/// opens the site in a new one, launching Chrome when needed.
struct SidebarSiteTile: View {
    let site: SidebarPinnedSite
    var dimsClosedSuperPin = false
    /// In a place of the full sidebar, the one in front has a small bar of
    /// its icon's color at its foot (`SidebarActiveBar`).
    var showsActiveBar = false

    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var browserTabs = BrowserTabsService.shared
    @ObservedObject private var favicons = SidebarFaviconStore.shared
    @ObservedObject private var sidebar = SidebarPreferences.shared
    @State private var isHovered = false

    private static let ink = Color.primary.opacity(0.74)

    private var openTab: BrowserTab? {
        browserTabs.tab(for: site)
    }

    /// A tab on the site shows unread items in its title.
    private var hasBadge: Bool {
        DockyPreferences.shared.showsAppBadges
            && (browserTabs.tabs ?? []).contains { site.matches($0.url) && $0.unreadCount != nil }
    }

    private var isCurrent: Bool {
        guard let openTab else { return false }
        return workspace.frontmostBundleIdentifier == BrowserTabsService.browserBundleIdentifier
            && openTab.isActive && openTab.isInFrontWindow
    }

    private var isSuperPin: Bool {
        sidebar.isSuperPin(SidebarPinnedItem.site(site).id)
    }

    var body: some View {
        Button {
            browserTabs.openOrFocus(site)
        } label: {
            icon
                .frame(width: SidebarMetrics.tileIconSize, height: SidebarMetrics.tileIconSize)
                .opacity(dimsClosedSuperPin && isSuperPin && openTab == nil ? 0.5 : 1)
                .frame(maxWidth: .infinity)
                .frame(height: SidebarMetrics.tileHeight)
                // Every tile alike, the way Arc draws its favorites: the
                // one in front raised, nothing greyed out, and no dot for
                // an open one: a pinned item on the bar is an open one,
                // the closed ones wait behind "+N" (Bruno, 27 October).
                // A tile wearing a Notion icon is washed with its color.
                .background(SidebarItemBackground(
                    isHovered: isHovered,
                    isCurrent: isCurrent,
                    restingOpacity: 0.07,
                    cornerRadius: SidebarMetrics.tileCornerRadius,
                    notionIcon: sidebar.wornIcon(forItem: SidebarPinnedItem.site(site).id),
                    outlined: true,
                    superPinLineWidth: isSuperPin ? 1.25 : nil,
                    superPinItemID: SidebarPinnedItem.site(site).id
                ))
                .overlay(alignment: .bottom) {
                    if showsActiveBar, isCurrent {
                        SidebarActiveBar(itemID: SidebarPinnedItem.site(site).id)
                    }
                }
                // A site, not an app: a small globe in the top left corner,
                // clear of the unread dot, the number and an account photo.
                .overlay(alignment: .topLeading) {
                    SidebarSiteMark()
                        .padding(3)
                }
                .overlay(alignment: .topTrailing) {
                    if hasBadge {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .padding(4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(site.title.isEmpty ? (site.host ?? site.url.absoluteString) : site.title)
        .overlay {
            SidebarContextMenuArea(
                actionProvider: { _ in sidebarSiteContextActions(for: site) },
                preferredEdge: .maxX
            )
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let custom = SidebarPreferences.shared.wornIcon(forItem: SidebarPinnedItem.site(site).id) {
            SidebarItemIconView(icon: custom, size: SidebarMetrics.tileIconSize)
        } else {
            SidebarWebIcon(url: openTab?.url ?? site.url, size: SidebarMetrics.tileIconSize)
        }
    }
}

/// One app as a tile: icon only, name in the tooltip. Used by the grid of
/// pinned apps and by every app in the compact rail.
struct SidebarAppTile: View {
    let app: AppTile
    var dimsClosedSuperPin = false
    /// In a place of the full sidebar, the one in front has a small bar of
    /// its icon's color at its foot (`SidebarActiveBar`).
    var showsActiveBar = false

    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var badges = DockBadgeService.shared
    @Bindable private var preferences = DockyPreferences.shared
    @ObservedObject private var sidebar = SidebarPreferences.shared
    @State private var isHovered = false

    private var isFrontmost: Bool {
        workspace.frontmostBundleIdentifier == app.bundleIdentifier
    }

    private var hasBadge: Bool {
        preferences.showsAppBadges && badges.badge(forBundleIdentifier: app.bundleIdentifier) != nil
    }

    private var isSuperPin: Bool {
        sidebar.isSuperPin(SidebarPinnedItem.app(app).id)
    }

    var body: some View {
        Button {
            workspace.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        } label: {
            SidebarAppIcon(bundleIdentifier: app.bundleIdentifier, size: SidebarMetrics.tileIconSize)
                .opacity(dimsClosedSuperPin && isSuperPin && !workspace.isRunning(bundleIdentifier: app.bundleIdentifier) ? 0.5 : 1)
                .frame(maxWidth: .infinity)
                .frame(height: SidebarMetrics.tileHeight)
                // Every tile alike, the way Arc draws its favorites: the
                // one in front raised, nothing greyed out, and no dot for
                // an open one: a pinned item on the bar is an open one,
                // the closed ones wait behind "+N" (Bruno, 27 October).
                // A tile wearing a Notion icon is washed with its color.
                .background(SidebarItemBackground(
                    isHovered: isHovered,
                    isCurrent: isFrontmost,
                    restingOpacity: 0.07,
                    cornerRadius: SidebarMetrics.tileCornerRadius,
                    notionIcon: sidebar.wornIcon(forItem: SidebarPinnedItem.app(app).id),
                    outlined: true,
                    superPinLineWidth: isSuperPin ? 1.25 : nil,
                    superPinItemID: SidebarPinnedItem.app(app).id
                ))
                .overlay(alignment: .bottom) {
                    if showsActiveBar, isFrontmost {
                        SidebarActiveBar(itemID: SidebarPinnedItem.app(app).id)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if hasBadge {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .padding(4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(app.displayName)
        .overlay {
            SidebarContextMenuArea(
                actionProvider: { flags in sidebarAppContextActions(for: app, modifierFlags: flags) },
                preferredEdge: .maxX
            )
        }
    }
}

// MARK: - Pinned folders

/// A folder pinned to the dock: one of Docky's app folders, or a Finder
/// folder.
enum SidebarPinnedFolder: Identifiable, Equatable {
    case apps(AppFolderTile)
    case finder(FolderTile)

    var id: String {
        switch self {
        case .apps(let folder): "apps:\(folder.identifier)"
        case .finder(let folder): "path:\(folder.url.path)"
        }
    }

    var name: String {
        switch self {
        case .apps(let folder): folder.displayName
        case .finder(let folder): folder.displayName
        }
    }
}

/// Takes a folder out of the pinned block. A Finder folder simply leaves
/// it; an app folder is taken apart, and its apps go back among the pinned
/// apps, so no app is lost along with the folder.
func sidebarUnpin(_ folder: SidebarPinnedFolder) {
    let store = TileStore.shared
    for tile in store.tiles {
        switch (folder, tile.content) {
        case (.apps(let target), .appFolder(let candidate)) where candidate.identifier == target.identifier:
            store.ungroupAppFolder(tileID: tile.id)
            return
        case (.finder(let target), .folder(let candidate)) where candidate.url.standardizedFileURL == target.url.standardizedFileURL:
            store.removeTrailingItem(tileID: tile.id)
            return
        default:
            continue
        }
    }
}

/// Asks for a folder and pins it, after the other folders and before the
/// Trash.
func sidebarPinFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.prompt = "Pin"
    panel.message = "Choose folders to pin to the sidebar"
    NSApp.activate()

    guard panel.runModal() == .OK else { return }
    let store = TileStore.shared
    for url in panel.urls {
        let items = DockyPreferences.shared.trailingItems
        let alreadyPinned = store.tiles.contains { tile in
            if case .folder(let folder) = tile.content {
                return folder.url.standardizedFileURL == url.standardizedFileURL
            }
            return false
        }
        guard !alreadyPinned else { continue }
        let trashIndex = items.firstIndex { $0.kind == .trash } ?? items.count
        store.insertTrailingItem(
            .folder(url: url, displayName: FileManager.default.displayName(atPath: url.path)),
            at: trashIndex
        )
    }
}

/// A folder as a tile the size of an app tile, drawn like a project's icon
/// in Claude: a line symbol on a soft wash of its own color. The symbol
/// and the color are picked from the tile's right-click menu. Clicking the
/// tile lists the folder's contents under the block of tiles.
struct SidebarFolderTileView: View {
    let folder: SidebarPinnedFolder
    let isCurrent: Bool
    let action: () -> Void

    @ObservedObject private var sidebar = SidebarPreferences.shared
    @ObservedObject private var iconPack = SidebarIconPack.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var glyph: SidebarFolderGlyph {
        sidebar.glyph(forFolder: folder.id, named: folder.name)
    }

    var body: some View {
        let tint = Color(nsColor: glyph.tint.nsColor)
        let shape = RoundedRectangle(cornerRadius: SidebarMetrics.tileCornerRadius, style: .continuous)

        Button(action: action) {
            mark(tint: tint)
                .frame(maxWidth: .infinity)
                .frame(height: SidebarMetrics.tileHeight)
                .background(shape.fill(tint.opacity(washOpacity)))
                .overlay {
                    // The open folder is ringed in its own color rather
                    // than turned into the white pill of a current app.
                    shape.strokeBorder(tint.opacity(isCurrent ? 0.55 : 0), lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(folder.name)
        .accessibilityLabel(folder.name)
        .overlay {
            SidebarContextMenuArea(
                actionProvider: { _ in contextActions },
                preferredEdge: .maxX
            )
        }
    }

    /// The folder's icon from the custom pack when it has one, otherwise
    /// its symbol.
    @ViewBuilder
    private func mark(tint: Color) -> some View {
        if let packIcon = iconPack.icon(forFolderNamed: folder.name) {
            SidebarPackIconView(icon: packIcon, ink: tint)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: glyph.outlineSymbol)
                .font(.system(size: 13, weight: .light))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
        }
    }

    /// A faint wash: enough to tell the folders from the app tiles beside
    /// them, not enough to compete with the app icons.
    private var washOpacity: Double {
        let base = colorScheme == .dark ? 0.2 : 0.12
        if isCurrent {
            return base + 0.08
        }
        return isHovered ? base + 0.06 : base
    }

    private var contextActions: [ContextAction] {
        let current = glyph
        let identifier = folder.id
        let name = folder.name

        let symbolActions = SidebarFolderGlyph.choices.map { choice in
            ContextAction.action(
                choice.title,
                image: NSImage(systemSymbolName: choice.symbol, accessibilityDescription: nil),
                isOn: current.outlineSymbol == choice.symbol
            ) {
                SidebarPreferences.shared.setGlyphSymbol(choice.symbol, forFolder: identifier, named: name)
            }
        }

        let colorActions = SidebarFolderGlyph.Tint.allCases.map { tint in
            ContextAction.action(
                tint.title,
                image: Self.swatch(for: tint),
                isOn: current.tint == tint
            ) {
                SidebarPreferences.shared.setGlyphColor(tint, forFolder: identifier, named: name)
            }
        }

        var actions: [ContextAction] = [
            .submenu("Icon", children: symbolActions),
            .submenu("Color", children: colorActions),
            .divider
        ]
        if case .finder(let finderFolder) = folder {
            actions.append(.action("Open in Finder") {
                NSWorkspace.shared.open(finderFolder.url)
            })
        }
        let pinned = folder
        actions.append(.action("Unpin") {
            sidebarUnpin(pinned)
        })
        return actions
    }

    private static func swatch(for tint: SidebarFolderGlyph.Tint) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [tint.nsColor])
        return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}

/// What is inside the folder whose tile is selected, listed under the
/// block of tiles. Each row opens its app or file.
struct SidebarFolderContents: View {
    let folder: SidebarPinnedFolder
    let close: () -> Void

    @ObservedObject private var folderAccess = FolderAccessService.shared
    @State private var items: [SidebarFolderItem] = []
    @State private var hasLoaded = false

    /// More than this and the folder is better browsed in Finder.
    private static let itemLimit = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header

            switch folder {
            case .apps(let appFolder):
                ForEach(appFolder.apps, id: \.bundleIdentifier) { app in
                    SidebarFolderAppRow(app: app)
                }
            case .finder:
                if items.isEmpty {
                    Text(hasLoaded ? "Empty" : "Loading…")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, SidebarMetrics.rowPadding)
                        .frame(height: SidebarMetrics.rowHeight)
                } else {
                    ForEach(items) { item in
                        SidebarFolderItemRow(item: item)
                    }
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .task(id: "\(folder.id)-\(folderAccess.changeToken)") {
            await load()
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            Text(folder.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if case .finder(let finderFolder) = folder {
                SidebarRowButton(systemName: "arrow.up.forward", help: "Open in Finder") {
                    NSWorkspace.shared.open(finderFolder.url)
                }
            }

            SidebarRowButton(systemName: "xmark", help: "Close", action: close)
        }
        .padding(.leading, SidebarMetrics.rowPadding)
        .padding(.trailing, 2)
        .frame(height: 22)
    }

    private func load() async {
        guard case .finder(let finderFolder) = folder else { return }
        let urls = await FolderAccessService.shared.refreshedSortedContents(
            of: finderFolder.url,
            sortMode: finderFolder.sortMode
        )
        guard !Task.isCancelled else { return }

        var loaded: [SidebarFolderItem] = []
        for url in urls.prefix(Self.itemLimit) {
            let name = FileManager.default.displayName(atPath: url.path)
            loaded.append(SidebarFolderItem(url: url, name: name))
        }
        items = loaded
        hasLoaded = true
    }
}

private struct SidebarFolderAppRow: View {
    let app: AppTile

    @ObservedObject private var workspace = WorkspaceService.shared
    @State private var isHovered = false

    private var isRunning: Bool {
        workspace.isRunning(bundleIdentifier: app.bundleIdentifier)
    }

    var body: some View {
        Button {
            workspace.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        } label: {
            HStack(spacing: SidebarMetrics.rowSpacing) {
                SidebarAppIcon(bundleIdentifier: app.bundleIdentifier, size: SidebarMetrics.rowIconSize)

                Text(app.displayName)
                    .font(.system(size: SidebarMetrics.rowFontSize))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isRunning {
                    Circle()
                        .fill(Color.primary.opacity(0.45))
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, SidebarMetrics.rowPadding)
            .frame(height: SidebarMetrics.rowHeight)
            .background(SidebarItemBackground(
                isHovered: isHovered,
                isCurrent: workspace.frontmostBundleIdentifier == app.bundleIdentifier
            ))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .overlay {
            SidebarContextMenuArea(
                actionProvider: { flags in sidebarAppContextActions(for: app, modifierFlags: flags) },
                preferredEdge: .maxX
            )
        }
    }
}

struct SidebarFolderItem: Identifiable, Equatable {
    let url: URL
    let name: String

    var id: URL { url }
}

private struct SidebarFolderItemRow: View {
    let item: SidebarFolderItem

    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(item.url)
        } label: {
            HStack(spacing: SidebarMetrics.rowSpacing) {
                Image(nsImage: IconCacheService.shared.icon(forFileURL: item.url))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: SidebarMetrics.rowIconSize, height: SidebarMetrics.rowIconSize)

                Text(item.name)
                    .font(.system(size: SidebarMetrics.rowFontSize))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, SidebarMetrics.rowPadding)
            .frame(height: SidebarMetrics.rowHeight)
            .background(SidebarItemBackground(isHovered: isHovered, isCurrent: false))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.name)
    }
}

/// A symbol in a tile the size of the app tiles: the Trash, and the "+"
/// of the compact rail.
struct SidebarSymbolTile: View {
    let systemName: String
    let help: String
    var restingOpacity: Double = 0.07
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: SidebarMetrics.tileHeight)
                .background(SidebarItemBackground(
                    isHovered: isHovered,
                    isCurrent: false,
                    restingOpacity: restingOpacity,
                    cornerRadius: SidebarMetrics.tileCornerRadius
                ))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The Trash as a tile, opened through Finder like the dock's Trash tile.
struct SidebarTrashTile: View {
    @ObservedObject private var trash = TrashService.shared

    var body: some View {
        SidebarSymbolTile(
            systemName: trash.isEmpty ? "trash" : "trash.fill",
            help: String(localized: "Trash")
        ) {
            Task {
                _ = await AppleScriptService.shared.openTrash()
            }
        }
        .overlay {
            SidebarContextMenuArea(
                actionProvider: { _ in
                    [.action("Unpin") { SidebarPreferences.shared.showsTrash = false }]
                },
                preferredEdge: .maxX
            )
        }
    }
}

// MARK: - Open apps

/// One open app, the sidebar's "tab". Clicking the row brings the app
/// forward; the chevron that appears on the right while the pointer is on
/// the row unfolds its windows underneath.
struct SidebarOpenAppSection: View {
    let app: RunningApp
    let windows: [AppWindow]

    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var sidebar = SidebarPreferences.shared
    @ObservedObject private var badges = DockBadgeService.shared
    @Bindable private var preferences = DockyPreferences.shared
    @State private var isHovered = false

    private var isOpen: Bool {
        !windows.isEmpty && sidebar.expandedAppIdentifiers.contains(app.bundleIdentifier)
    }

    private var isFrontmost: Bool {
        workspace.frontmostBundleIdentifier == app.bundleIdentifier
    }

    private var appTile: AppTile {
        AppTile(bundleIdentifier: app.bundleIdentifier, displayName: app.localizedName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row

            if isOpen {
                ForEach(windows) { window in
                    SidebarWindowRow(window: window, appName: app.localizedName)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }

    private var row: some View {
        HStack(spacing: SidebarMetrics.rowSpacing) {
            SidebarAppIcon(bundleIdentifier: app.bundleIdentifier, size: SidebarMetrics.rowIconSize)
                .opacity(app.isHidden ? 0.5 : 1)

            Text(app.localizedName)
                .font(.system(size: SidebarMetrics.rowFontSize, weight: isFrontmost ? .medium : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            trailing
        }
        .padding(.leading, SidebarMetrics.rowPadding)
        .padding(.trailing, 5)
        .frame(height: SidebarMetrics.rowHeight)
        .background(SidebarItemBackground(isHovered: isHovered, isCurrent: isFrontmost))
        .contentShape(Rectangle())
        .onTapGesture {
            workspace.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        }
        .onHover { isHovered = $0 }
        .overlay {
            SidebarContextMenuArea(
                actionProvider: { flags in sidebarAppContextActions(for: appTile, modifierFlags: flags) },
                preferredEdge: .maxX
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) {
            workspace.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        }
        .accessibilityAction(named: isOpen ? "Hide windows" : "Show windows") {
            sidebar.toggleExpansion(ofApp: app.bundleIdentifier)
        }
    }

    /// Right side of the row. At rest, only the unread badge. Under the
    /// pointer: the chevron that unfolds the app's windows, when it has
    /// any, then the quit button at the very end, where a close button is
    /// expected.
    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 2) {
            if isHovered {
                // Only under the pointer: a chevron on every row is a
                // column of noise down the side of the list. It points
                // down, the way the windows unfold, and up once they have.
                if !windows.isEmpty {
                    Button {
                        withAnimation(SidebarMetrics.foldAnimation) {
                            sidebar.toggleExpansion(ofApp: app.bundleIdentifier)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isOpen ? "Hide windows" : "Show windows")
                }

                SidebarRowButton(systemName: "xmark", help: "Quit \(app.localizedName)") {
                    workspace.quit(bundleIdentifier: app.bundleIdentifier)
                }
            } else if preferences.showsAppBadges, let badge = badges.badge(forBundleIdentifier: app.bundleIdentifier) {
                SidebarBadge(text: badge)
            }
        }
    }
}

private struct SidebarWindowRow: View {
    let window: AppWindow
    let appName: String

    @State private var isHovered = false

    private var title: String {
        let trimmed = window.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(window.isMinimized ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if isHovered {
                SidebarRowButton(systemName: "xmark", help: "Close window") {
                    _ = WorkspaceService.shared.close(window: window)
                }
            } else if window.isMinimized {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18)
            }
        }
        .padding(.leading, SidebarMetrics.nestedIndent)
        .padding(.trailing, 5)
        .frame(height: 24)
        .background(SidebarItemBackground(isHovered: isHovered, isCurrent: false, cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            _ = WorkspaceService.shared.focus(window: window)
        }
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) {
            _ = WorkspaceService.shared.focus(window: window)
        }
    }
}

/// A web page's icon, from the first of these that has one:
///
///   1. the icon Chrome shows for that very page (`ChromeFaviconStore`),
///      which knows pages behind a sign-in and icons set from script;
///   2. the icon of the page's site, fetched from the web
///      (`SidebarFaviconStore`);
///   3. the first letter of the site's name on a quiet tile, the way a
///      folder shows its symbol; a globe for a page with no site at all.
struct SidebarWebIcon: View {
    let url: URL?
    let size: CGFloat

    @ObservedObject private var chromeFavicons = ChromeFaviconStore.shared
    @ObservedObject private var favicons = SidebarFaviconStore.shared

    private static let ink = Color.primary.opacity(0.74)

    var body: some View {
        if let image = chromeFavicons.icon(for: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else if let host = url.flatMap(SidebarPinnedSite.host(of:)), let favicon = favicons.icon(forSite: host) {
            SidebarPackIconView(icon: favicon, ink: Self.ink)
                .frame(width: size, height: size)
        } else if let letter = url.flatMap(Self.initial(of:)) {
            SidebarLetterIcon(letter: letter, tint: Self.ink, size: size)
        } else {
            SidebarAppSymbolView(systemName: "globe", tint: Self.ink, size: size)
        }
    }

    /// The first letter of the site's own name, its subdomains and ending
    /// left aside: "mail.google.com" -> "G", "lemonde.fr" -> "L". Nil for
    /// an address with no name to take it from (an IP, a local page).
    static func initial(of url: URL) -> String? {
        guard let host = SidebarPinnedSite.host(of: url) else { return nil }
        let labels = host.split(separator: ".")
        guard labels.count >= 2, !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        let name = labels[labels.count - 2]
        guard let first = name.first(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return String(first).uppercased()
    }
}

/// A site with no icon of its own: its initial on the same quiet tile as
/// the symbols, so it reads as a placeholder and not as some other site.
struct SidebarLetterIcon: View {
    let letter: String
    let tint: Color
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(letter)
            .font(.system(size: size * 0.58, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.24 : 0.15))
            )
    }
}

/// A Chrome tab, in the Web group under the open apps: the site's icon,
/// the page's title, the white pill when it is the tab in front, and
/// a close button under the pointer.
struct SidebarBrowserTabRow: View {
    let tab: BrowserTab

    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var favicons = SidebarFaviconStore.shared
    @State private var isHovered = false

    private static let ink = Color.primary.opacity(0.74)

    private var isCurrent: Bool {
        workspace.frontmostBundleIdentifier == BrowserTabsService.browserBundleIdentifier
            && tab.isActive && tab.isInFrontWindow
    }

    private var title: String {
        let trimmed = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (tab.host ?? "New Tab") : trimmed
    }

    var body: some View {
        HStack(spacing: SidebarMetrics.rowSpacing) {
            icon
                .frame(width: SidebarMetrics.rowIconSize, height: SidebarMetrics.rowIconSize)

            Text(title)
                .font(.system(size: SidebarMetrics.rowFontSize, weight: isCurrent ? .medium : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if isHovered {
                SidebarRowButton(systemName: "xmark", help: "Close tab") {
                    BrowserTabsService.shared.close(tab)
                }
            } else if DockyPreferences.shared.showsAppBadges, let count = tab.unreadCount {
                SidebarBadge(text: count)
            }
        }
        .padding(.leading, SidebarMetrics.rowPadding)
        .padding(.trailing, 5)
        .frame(height: SidebarMetrics.rowHeight)
        .background(SidebarItemBackground(isHovered: isHovered, isCurrent: isCurrent))
        .contentShape(Rectangle())
        .onTapGesture {
            BrowserTabsService.shared.focus(tab)
        }
        .onHover { isHovered = $0 }
        .help(tab.url?.absoluteString ?? title)
        .overlay {
            SidebarContextMenuArea(
                actionProvider: { _ in pinActions },
                preferredEdge: .maxX
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) {
            BrowserTabsService.shared.focus(tab)
        }
    }

    /// "Pin" puts the tab's site among the pinned apps; "Unpin" takes it
    /// back out.
    private var pinActions: [ContextAction] {
        guard let url = tab.url, tab.host != nil else { return [] }
        let preferences = SidebarPreferences.shared
        let title = self.title
        let tab = self.tab
        let pinActions: [ContextAction]
        if let site = preferences.pinnedSite(for: url) {
            pinActions = [
                .action("Unpin") {
                    preferences.move(item: SidebarPinnedItem.site(site).id, to: .top)
                    preferences.unpin(site)
                },
                sidebarMoveAction(forItem: SidebarPinnedItem.site(site).id)
            ]
        } else {
            pinActions = [SidebarPlace.top, .bottom].map { place in
                .action(place.pinTitle) {
                    preferences.pin(site: url, title: title)
                    if let site = preferences.pinnedSite(for: url) {
                        preferences.move(item: SidebarPinnedItem.site(site).id, to: place)
                    }
                }
            }
        }
        return pinActions + [
            .divider,
            .action("Close Tab") { BrowserTabsService.shared.close(tab) }
        ]
    }

    private var icon: some View {
        SidebarWebIcon(url: tab.url, size: SidebarMetrics.rowIconSize)
    }
}

/// The title of a group of the open list ("Apps", "Web"). A click folds
/// or unfolds the group; folded, it shows how many items it holds. Under
/// the pointer it offers to close the whole group at once.
struct SidebarGroupHeader: View {
    let title: String
    let count: Int
    let isFolded: Bool
    /// The "close all" shown on hover; none when nil, as for the pinned
    /// items, which have nothing to close.
    var closeTitle: String? = nil
    let toggle: () -> Void
    var close: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            // The title, then its chevron in the same color (Bruno, 28
            // October, as on Windows), then the count.
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isFolded ? 0 : 90))

            if isFolded, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }

            Spacer(minLength: 0)

            if isHovered, count > 0, let closeTitle, let close {
                Button(action: close) {
                    Text(closeTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.leading, SidebarMetrics.rowPadding)
        .padding(.trailing, 5)
        .frame(height: 22)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAction(named: isFolded ? "Show" : "Hide", toggle)
    }
}

// MARK: - Plain rows

/// A row that runs an action: "New Window", the Trash. `isQuiet` greys it
/// the way a browser greys "New Tab" under the open tabs.
struct SidebarActionRow: View {
    let systemName: String
    let title: String
    var isQuiet = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SidebarMetrics.rowSpacing) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: SidebarMetrics.rowIconSize)

                Text(title)
                    .font(.system(size: SidebarMetrics.rowFontSize))
                    .foregroundStyle(isQuiet ? .secondary : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, SidebarMetrics.rowPadding)
            .frame(height: SidebarMetrics.rowHeight)
            .background(SidebarItemBackground(isHovered: isHovered, isCurrent: false))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A short, clickable note inside the list, for a missing permission.
struct SidebarHintRow: View {
    let systemName: String
    let text: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: SidebarMetrics.rowSpacing) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: SidebarMetrics.rowIconSize)
                    .padding(.top, 1)

                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, SidebarMetrics.rowPadding)
            .padding(.vertical, 6)
            .background(SidebarItemBackground(isHovered: isHovered, isCurrent: false, restingOpacity: 0.05))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Small controls

/// Small square button at the right end of a row: close, quit, open in
/// Finder.
struct SidebarRowButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// Header button: the rail toggle, and the "+" of the compact rail.
struct SidebarIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

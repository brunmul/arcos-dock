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
import SwiftUI

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
    /// Four tiles across, for the pinned apps and the pinned folders.
    static let tileColumns = Array(
        repeating: GridItem(.flexible(minimum: 32), spacing: tileSpacing),
        count: 4
    )
    static let foldAnimation = Animation.spring(response: 0.28, dampingFraction: 0.86)
}

/// An app's icon, from the first of these that applies:
///
///   1. the custom icon pack (`SidebarIconPack`), for the apps it covers;
///   2. with tinted icons on, a glyph cut out of the app's icon and drawn
///      in the icon's main color (`SidebarIconGlyph`);
///   3. the icon picked with "Change Icon...", or the app's own.
struct SidebarAppIcon: View {
    let bundleIdentifier: String
    let size: CGFloat

    @Bindable private var preferences = DockyPreferences.shared
    @ObservedObject private var iconPack = SidebarIconPack.shared
    @ObservedObject private var sidebar = SidebarPreferences.shared

    private static let ink = Color.primary.opacity(0.74)

    var body: some View {
        if let packIcon = iconPack.icon(forBundleIdentifier: bundleIdentifier) {
            SidebarPackIconView(icon: packIcon, ink: Self.ink)
                .frame(width: size, height: size)
        } else if sidebar.usesTintedIcons, let glyph = SidebarIconGlyph.glyph(for: image, key: glyphKey) {
            Image(nsImage: glyph.image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(glyph.tint.map { Color(nsColor: $0) } ?? Self.ink)
                .frame(width: size, height: size)
        } else {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
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

    let syntheticTile = Tile(content: .app(app))
    let baseActions = MenuCatalogService.shared
        .contextActions(for: syntheticTile, modifierFlags: modifierFlags) ?? []
    let windows = WorkspaceService.shared.appWindows(bundleIdentifier: app.bundleIdentifier)
    let withWindows = injectingAppWindowActions(windows, into: baseActions)
    let withIcon = injectingCustomIconActions(into: withWindows, for: app)

    guard let pinAction = sidebarPinAction(for: app) else { return withIcon }
    return withIcon.isEmpty ? [pinAction] : [pinAction, .divider] + withIcon
}

/// "Pin" for an open app that is not among the pinned tiles, "Unpin" for
/// one that is. Nil for Finder, which the dock always keeps.
private func sidebarPinAction(for app: AppTile) -> ContextAction? {
    let bundleIdentifier = app.bundleIdentifier
    guard bundleIdentifier != "com.apple.finder" else { return nil }

    let isPinned = TileStore.shared.tiles.contains { tile in
        guard tile.id.hasPrefix("pinned:"), case .app(let pinned) = tile.content else { return false }
        return pinned.bundleIdentifier == bundleIdentifier
    }

    return .action(isPinned ? "Unpin" : "Pin") {
        TileStore.shared.setPinnedApp(bundleIdentifier: bundleIdentifier, pinned: !isPinned)
    }
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
private struct SidebarBadge: View {
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

/// Background shared by every row and tile: nothing at rest, a faint wash
/// under the pointer, and a light raised pill for the current item, the
/// way a browser marks the active tab.
struct SidebarItemBackground: View {
    let isHovered: Bool
    let isCurrent: Bool
    var restingOpacity: Double = 0
    var cornerRadius: CGFloat = 7

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .shadow(color: .black.opacity(isCurrent ? 0.1 : 0), radius: 1.5, x: 0, y: 0.5)
    }

    private var fill: Color {
        if isCurrent {
            return Color.white.opacity(colorScheme == .dark ? 0.18 : 0.78)
        }
        return Color.primary.opacity(isHovered ? restingOpacity + 0.06 : restingOpacity)
    }
}

// MARK: - Pinned apps

/// Pinned apps as a grid of small tiles, like the favorites at the top of
/// Arc's sidebar. A dot marks the ones that are running.
struct SidebarFavoritesGrid: View {
    let apps: [AppTile]

    var body: some View {
        LazyVGrid(columns: SidebarMetrics.tileColumns, spacing: SidebarMetrics.tileSpacing) {
            ForEach(apps, id: \.bundleIdentifier) { app in
                SidebarAppTile(app: app)
            }
        }
    }
}

/// One app as a tile: icon only, name in the tooltip. Used by the grid of
/// pinned apps and by every app in the compact rail.
struct SidebarAppTile: View {
    let app: AppTile

    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var badges = DockBadgeService.shared
    @Bindable private var preferences = DockyPreferences.shared
    @State private var isHovered = false

    private var isRunning: Bool {
        workspace.isRunning(bundleIdentifier: app.bundleIdentifier)
    }

    private var isFrontmost: Bool {
        workspace.frontmostBundleIdentifier == app.bundleIdentifier
    }

    private var hasBadge: Bool {
        preferences.showsAppBadges && badges.badge(forBundleIdentifier: app.bundleIdentifier) != nil
    }

    var body: some View {
        Button {
            workspace.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        } label: {
            SidebarAppIcon(bundleIdentifier: app.bundleIdentifier, size: SidebarMetrics.tileIconSize)
                .frame(maxWidth: .infinity)
                .frame(height: SidebarMetrics.tileHeight)
                .background(SidebarItemBackground(
                    isHovered: isHovered,
                    isCurrent: isFrontmost,
                    restingOpacity: 0.07,
                    cornerRadius: SidebarMetrics.tileCornerRadius
                ))
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(Color.primary.opacity(isRunning ? 0.45 : 0))
                        .frame(width: 8, height: 2)
                        .padding(.bottom, 2.5)
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
        .background {
            ContextActionMenuPresenter(
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
        .background {
            ContextActionMenuPresenter(
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
            .submenu("Color", children: colorActions)
        ]
        if case .finder(let finderFolder) = folder {
            actions.append(.divider)
            actions.append(.action("Open in Finder") {
                NSWorkspace.shared.open(finderFolder.url)
            })
        }
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
        .background {
            ContextActionMenuPresenter(
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
        .background {
            ContextActionMenuPresenter(
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
    /// pointer, the quit button and, when the app has windows to show, the
    /// chevron that unfolds them.
    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 2) {
            if isHovered {
                SidebarRowButton(systemName: "xmark", help: "Quit \(app.localizedName)") {
                    workspace.quit(bundleIdentifier: app.bundleIdentifier)
                }
            } else if preferences.showsAppBadges, let badge = badges.badge(forBundleIdentifier: app.bundleIdentifier) {
                SidebarBadge(text: badge)
            }

            // Only under the pointer: a chevron on every row is a column
            // of noise down the side of the list.
            if !windows.isEmpty, isHovered {
                Button {
                    withAnimation(SidebarMetrics.foldAnimation) {
                        sidebar.toggleExpansion(ofApp: app.bundleIdentifier)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isOpen ? "Hide windows" : "Show windows")
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

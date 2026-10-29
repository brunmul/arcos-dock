//
//  SidebarView.swift
//  Docky
//
//  Content of the sidebar. It follows the layout of Arc's sidebar, top to
//  bottom:
//
//    header      Docky's icon, which opens Settings, then the full /
//                compact toggle and a menu (settings, back to the dock
//                strip, quit)
//    pinned      a group that folds: the pinned apps and sites, and any
//                widget moved up, as tiles or rows ("…" → Layout); then
//                the pinned folders and the Trash. A folder's tile lists
//                its contents underneath
//    open        two groups that fold, each with a "close all": Apps,
//                every open app, a row unfolding into the app's windows,
//                ending with "New Window"; then Web, one row per Chrome
//                tab (`BrowserTabsService`), which takes Chrome's place
//                among the apps, ending with "New Tab". Both open a
//                search (`SidebarSearch.swift`)
//    widgets     the dock's widgets, and any pinned app or site moved
//                down, as rows the size of an app's row or as tiles; a
//                widget's detail opens beside the sidebar on hover
//                (`SidebarWidgets.swift`)
//
//  Compact, the same content becomes a rail of icons, like the collapsed
//  vertical tabs of Chrome or Brave.
//
//  Everything is read from the stores the dock strip already uses
//  (`TileStore`, `WorkspaceService`, `WindowRegistry`), so both
//  presentations always show the same apps, folders and widgets.
//

import AppKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject private var tileStore = TileStore.shared
    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var windowRegistry = WindowRegistry.shared
    @ObservedObject private var sidebar = SidebarPreferences.shared
    @ObservedObject private var permissions = PermissionsService.shared
    @ObservedObject private var browserTabs = BrowserTabsService.shared
    @Bindable private var preferences = DockyPreferences.shared

    @AppStorage("docky.fork.sidebar.foldsPinned") private var foldsPinned = false
    @AppStorage("docky.fork.sidebar.foldsApps") private var foldsApps = false
    @AppStorage("docky.fork.sidebar.foldsWeb") private var foldsWeb = false

    private static let horizontalPadding: CGFloat = 8

    var body: some View {
        Group {
            if sidebar.isBottom {
                SidebarBottomBar(
                    pinnedItems: pinnedItems,
                    pinnedFolders: pinnedFolders,
                    showsTrash: showsTrash,
                    otherOpenApps: railOpenApps,
                    otherTabs: railTabs,
                    widgets: widgets
                )
            } else if sidebar.isCompact {
                SidebarRail(
                    pinnedItems: pinnedItems,
                    pinnedFolders: pinnedFolders,
                    showsTrash: showsTrash,
                    otherOpenApps: railOpenApps,
                    otherTabs: railTabs,
                    widgets: widgets
                )
            } else {
                fullSidebar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SidebarChrome())
        .sidebarThemeScheme(sidebar.theme)
    }

    private var fullSidebar: some View {
        VStack(spacing: 0) {
            SidebarHeader()
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 10)

            // The pinned apps and sites at the top stay put: scrolling the
            // folders, Apps and Web never hides them (Bruno, 28 October).
            VStack(alignment: .leading, spacing: 1) {
                pinnedSection
            }
            .padding(.horizontal, Self.horizontalPadding)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    if !foldsPinned {
                        pinnedFolderTiles
                    }

                    SidebarDivider()
                        .padding(.vertical, 6)

                    openSection
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.bottom, 6)
            }
            .frame(minHeight: 80)

            if !bottomWidgets.isEmpty || !bottomItems.isEmpty {
                SidebarDivider()
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.bottom, 6)

                SidebarPlaceView(items: bottomItems, widgets: bottomWidgets, layout: sidebar.bottomLayout, allItemIDs: pinnedItems.map(\.id))
                    .padding(.horizontal, Self.horizontalPadding)
            }
        }
        .padding(.bottom, 8)
    }

    /// Everything pinned to the dock, as two small blocks of tiles: the
    /// apps, fixed at the top, then the folders and the Trash, which
    /// scroll with the lists (`pinnedFolderTiles`). The folder whose tile
    /// is selected lists its contents underneath. Both fold under the
    /// header like Apps and Web.
    @ViewBuilder
    private var pinnedSection: some View {
        SidebarGroupHeader(
            title: "Pinned",
            count: topItems.count + topWidgets.count,
            isFolded: foldsPinned,
            toggle: { withAnimation(SidebarMetrics.foldAnimation) { foldsPinned.toggle() } }
        )
        .padding(.bottom, foldsPinned ? 0 : 3)
        if !foldsPinned, !topItems.isEmpty || !topWidgets.isEmpty {
            SidebarPlaceView(items: topItems, widgets: topWidgets, layout: sidebar.topLayout, allItemIDs: pinnedItems.map(\.id))
        }
    }

    @ViewBuilder
    private var pinnedFolderTiles: some View {
        let hasTopContent = !topItems.isEmpty || !topWidgets.isEmpty
        LazyVGrid(columns: SidebarMetrics.tileColumns, spacing: SidebarMetrics.tileSpacing) {
            ForEach(pinnedFolders) { folder in
                SidebarFolderTileView(
                    folder: folder,
                    isCurrent: sidebar.openFolderIdentifier == folder.id
                ) {
                    withAnimation(SidebarMetrics.foldAnimation) {
                        sidebar.toggleFolder(folder.id)
                    }
                }
            }

            if showsTrash {
                SidebarTrashTile()
            }
        }
        .padding(.top, hasTopContent ? 7 : 0)

        if let openFolder {
            SidebarFolderContents(folder: openFolder) {
                withAnimation(SidebarMetrics.foldAnimation) {
                    sidebar.openFolderIdentifier = nil
                }
            }
            .padding(.top, 6)
            .transition(.opacity)
        }
    }

    private var openFolder: SidebarPinnedFolder? {
        guard let identifier = sidebar.openFolderIdentifier else { return nil }
        return pinnedFolders.first { $0.id == identifier }
    }

    /// The open apps, then "New Window" the way a browser ends its tabs
    /// with "New Tab".
    @ViewBuilder
    private var openSection: some View {
        let tabs = listedTabs
        let apps = listedApps

        SidebarGroupHeader(
            title: "Apps",
            count: apps.count,
            isFolded: foldsApps,
            closeTitle: "Quit All",
            toggle: { withAnimation(SidebarMetrics.foldAnimation) { foldsApps.toggle() } },
            close: {
                for app in apps where app.bundleIdentifier != "com.apple.finder" {
                    workspace.quit(bundleIdentifier: app.bundleIdentifier)
                }
            }
        )
        if !foldsApps {
            ForEach(apps) { app in
                SidebarOpenAppSection(
                    app: app,
                    windows: windowRegistry.windows(forBundleIdentifier: app.bundleIdentifier)
                )
            }
            SidebarActionRow(systemName: "plus", title: "New Window", isQuiet: true) {
                SidebarSearchController.shared.toggle(.apps)
            }
        }

        SidebarGroupHeader(
            title: "Web",
            count: tabs.count,
            isFolded: foldsWeb,
            closeTitle: "Close All",
            toggle: { withAnimation(SidebarMetrics.foldAnimation) { foldsWeb.toggle() } },
            close: { browserTabs.closeAll() }
        )
        .padding(.top, 8)
        if !foldsWeb {
            ForEach(tabs) { tab in
                SidebarBrowserTabRow(tab: tab)
            }
            SidebarActionRow(systemName: "plus", title: "New Tab", isQuiet: true) {
                SidebarSearchController.shared.toggle(.web)
            }
        }

        if permissions.accessibility != .granted {
            SidebarHintRow(
                systemName: "macwindow.on.rectangle",
                text: "Allow Accessibility to keep windows out from under the sidebar and to unfold apps into their windows"
            ) {
                _ = PermissionsService.shared.requestAccessibilityPermission(prompt: true)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Data

    /// Apps pinned to the dock, in dock order.
    private var pinnedApps: [AppTile] {
        var apps: [AppTile] = []
        for tile in tileStore.tiles where tile.id.hasPrefix("pinned:") {
            if case .app(let app) = tile.content, !app.bundleIdentifier.isEmpty {
                apps.append(app)
            }
        }
        return apps
    }

    /// The pinned apps and sites as one list, the open ones first (an app
    /// running, a site with a tab), whichever kind they are; within each
    /// group, apps in dock order, then sites in pinning order.
    private var pinnedItems: [SidebarPinnedItem] {
        sidebar.ordered(pinnedApps.map(SidebarPinnedItem.app) + sidebar.pinnedSites.map(SidebarPinnedItem.site))
    }

    /// Every running app, oldest first, minus the ones hidden from Docky.
    private var openApps: [RunningApp] {
        workspace.runningApps.filter { app in
            !preferences.isAppHiddenInDocky(bundleIdentifier: app.bundleIdentifier)
        }
    }

    /// The Apps group: the open apps, minus Chrome while its tabs stand in
    /// for it in the Web group, and minus the pinned ones when they are to
    /// show only as tiles.
    private var listedApps: [RunningApp] {
        var apps = openApps
        if let tabs = browserTabs.tabs, !tabs.isEmpty {
            apps.removeAll { $0.bundleIdentifier == BrowserTabsService.browserBundleIdentifier }
        }
        if !sidebar.showsPinnedAppsInOpenList {
            let pinned = Set(pinnedApps.map(\.bundleIdentifier))
            apps.removeAll { pinned.contains($0.bundleIdentifier) }
        }
        return apps
    }

    /// The Web group: Chrome's tabs, minus those on a pinned site when the
    /// pinned items are to show only as tiles.
    private var listedTabs: [BrowserTab] {
        let tabs = browserTabs.tabs ?? []
        guard !sidebar.showsPinnedAppsInOpenList else { return tabs }
        return tabs.filter { sidebar.pinnedSite(for: $0.url) == nil }
    }

    /// The open apps in the compact rail: not pinned, and without Chrome
    /// while its tabs are listed one by one.
    private var railOpenApps: [RunningApp] {
        guard let tabs = browserTabs.tabs, !tabs.isEmpty else { return unpinnedOpenApps }
        return unpinnedOpenApps.filter { $0.bundleIdentifier != BrowserTabsService.browserBundleIdentifier }
    }

    /// The tabs in the compact rail: those on a pinned site already show
    /// as its tile.
    private var railTabs: [BrowserTab] {
        (browserTabs.tabs ?? []).filter { sidebar.pinnedSite(for: $0.url) == nil }
    }

    /// Open apps that are not pinned. The compact rail lists these under
    /// the pinned ones, so no icon shows up twice.
    private var unpinnedOpenApps: [RunningApp] {
        let pinned = Set(pinnedApps.map(\.bundleIdentifier))
        return openApps.filter { !pinned.contains($0.bundleIdentifier) }
    }

    /// The widgets shown, all together at the bottom (the events too):
    /// the dock's widgets minus those unticked in "…" → Widgets.
    private var widgets: [WidgetTile] {
        SidebarPreferences.allWidgets(in: tileStore).filter { sidebar.shows(widget: $0) }
    }

    /// The pinned apps and sites, and the widgets, split between the top
    /// of the full sidebar and its foot (`SidebarPreferences.bottomItemIDs`,
    /// `topWidgetIDs`). The rail and the bottom bar show them all as before.
    private var topItems: [SidebarPinnedItem] {
        pinnedItems.filter { sidebar.place(ofItem: $0.id) == .top }
    }

    private var bottomItems: [SidebarPinnedItem] {
        pinnedItems.filter { sidebar.place(ofItem: $0.id) == .bottom }
    }

    private var topWidgets: [WidgetTile] {
        widgets.filter { sidebar.place(of: $0) == .top }
    }

    private var bottomWidgets: [WidgetTile] {
        widgets.filter { sidebar.place(of: $0) == .bottom }
    }

    /// Docky's app folders and the Finder folders, in dock order.
    private var pinnedFolders: [SidebarPinnedFolder] {
        var folders: [SidebarPinnedFolder] = []
        for tile in tileStore.tiles {
            switch tile.content {
            case .appFolder(let folder):
                folders.append(.apps(folder))
            case .folder(let folder):
                folders.append(.finder(folder))
            default:
                break
            }
        }
        return folders
    }

    private var showsTrash: Bool {
        sidebar.showsTrash && tileStore.tiles.contains { tile in
            if case .trash = tile.content {
                return true
            }
            return false
        }
    }
}

// MARK: - Chrome

/// The sidebar's surface: opaque warm paper (see `SidebarPalette`), or the
/// chosen theme's gentle gradient. Opaque on purpose: the sidebar is meant
/// to read as part of the screen's frame, not as glass floating over the
/// desktop.
struct SidebarChrome: View {
    @ObservedObject private var sidebar = SidebarPreferences.shared

    var body: some View {
        // The theme in the mode in use; Claude's paper or charcoal is a
        // gradient of one color.
        let theme = sidebar.theme
        LinearGradient(
            colors: [Color(hex: theme.top), Color(hex: theme.bottom)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension Color {
    init(hex: Int) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// Light text on a dark theme, dark text on a light one. `theme` is
    /// the one in the mode in use (`SidebarPreferences.theme`), so this is
    /// the forced mode, or the system's in Auto.
    func sidebarThemeScheme(_ theme: SidebarTheme) -> some View {
        environment(\.colorScheme, theme.isDark ? .dark : .light)
    }
}

/// The two concave corners drawn just right of the sidebar, at the top and
/// the bottom, in the sidebar's own surface. They round off the area next
/// to the sidebar so the windows there look set into it.
struct SidebarCornersView: View {
    @ObservedObject private var sidebar = SidebarPreferences.shared

    var body: some View {
        VStack(spacing: 0) {
            corner(isTop: true)
            Spacer(minLength: 0)
            corner(isTop: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            // The outline that sets the sidebar apart from a window of the
            // same grey next to it. It runs down the sidebar's edge and
            // around both corners, on the window's side of them. A colored
            // theme stands apart on its own; there the line would only show
            // as a light seam.
            if sidebar.theme.isClaude {
                SidebarEdgeOutline()
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    .padding(.leading, 0.5)
            }
        }
        .allowsHitTesting(false)
        .sidebarThemeScheme(sidebar.theme)
    }

    /// Each corner in the color of the sidebar's end beside it.
    @ViewBuilder
    private func corner(isTop: Bool) -> some View {
        let theme = sidebar.theme
        Color(hex: isTop ? theme.top : theme.bottom)
        .frame(width: SidebarPreferences.cornerRadius, height: SidebarPreferences.cornerRadius)
        .clipShape(SidebarConcaveCorner(isTop: isTop))
    }
}

/// The sidebar's visible edge: down its right side, curving outwards along
/// the concave corner at each end. Drawn in the strip that holds the
/// corners, whose width is the corners' radius.
private struct SidebarEdgeOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addRelativeArc(
            center: CGPoint(x: rect.maxX, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            delta: .degrees(-90)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addRelativeArc(
            center: CGPoint(x: rect.maxX, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(180),
            delta: .degrees(-90)
        )
        return path
    }
}

/// A square with a quarter disc cut out of it: what is left of the corner
/// once the neighbouring area has been rounded. The square hugs the
/// sidebar on its left and the screen edge above (or below) it.
private struct SidebarConcaveCorner: Shape {
    let isTop: Bool

    func path(in rect: CGRect) -> Path {
        let radius = rect.width
        var path = Path()

        if isTop {
            // Disc centered on the square's bottom-right corner.
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addRelativeArc(
                center: CGPoint(x: rect.maxX, y: rect.maxY),
                radius: radius,
                startAngle: .degrees(-90),
                delta: .degrees(-90)
            )
        } else {
            // Disc centered on the square's top-right corner.
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addRelativeArc(
                center: CGPoint(x: rect.maxX, y: rect.minY),
                radius: radius,
                startAngle: .degrees(90),
                delta: .degrees(90)
            )
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Header

/// Docky's own icon on the left, which opens Settings, and the buttons
/// on the right.
private struct SidebarHeader: View {
    @ObservedObject private var sidebar = SidebarPreferences.shared

    var body: some View {
        HStack(spacing: 2) {
            SidebarAppMark()
            Spacer(minLength: 8)
            SidebarIconButton(systemName: "sidebar.left", help: "Show icons only") {
                sidebar.isCompact = true
            }
            SidebarOptionsMenu()
        }
        .frame(height: 24)
    }
}

/// Docky's app icon, where the Apple mark used to be: a click opens
/// Settings on the sidebar's panes.
struct SidebarAppMark: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            SettingsNavigator.shared.requestPane(id: "sidebarLayout")
        } label: {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}

/// The sidebar's options, behind "…": in the header down the left, and at
/// the end of the bar along the bottom.
private struct SidebarOptionsMenu: View {
    @ObservedObject private var sidebar = SidebarPreferences.shared

    var body: some View {
        Menu {
            // Every option lives in Settings → Sidebar.
            Button("Settings…") {
                SettingsNavigator.shared.requestPane(id: "sidebarLayout")
            }
            Divider()
            Button("Switch to Dock") {
                SidebarWindowController.shared.setSidebarMode(false)
            }
            Button("Quit Docky") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sidebar options")
    }
}

private struct SidebarDivider: View {
    var body: some View {
        SidebarWave()
            .padding(.horizontal, 4)
    }
}

// MARK: - Compact rail

/// The sidebar reduced to a column of icons. Pinned apps and sites,
/// pinned folders as tiles; then the other open apps and Chrome's other
/// tabs as a tighter list of bare icons, each list ending with "+"; and
/// the widgets. Clicking a folder opens the full sidebar on it.
private struct SidebarRail: View {
    let pinnedItems: [SidebarPinnedItem]
    let pinnedFolders: [SidebarPinnedFolder]
    let showsTrash: Bool
    let otherOpenApps: [RunningApp]
    let otherTabs: [BrowserTab]
    let widgets: [WidgetTile]

    @ObservedObject private var workspace = WorkspaceService.shared

    @ObservedObject private var sidebar = SidebarPreferences.shared

    private static let itemWidth: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            SidebarIconButton(systemName: "sidebar.left", help: "Show the full sidebar") {
                sidebar.isCompact = false
            }
            .padding(.top, 8)

            // The options stay within reach in every form of the bar.
            SidebarOptionsMenu()
                .padding(.bottom, 6)

            // The pinned items stay put above what scrolls (Bruno, 28
            // October), as in the full sidebar.
            if sidebar.shows(.pinned), !pinnedItems.isEmpty {
                VStack(spacing: 4) {
                    ForEach(pinnedItems) { item in
                        SidebarPinnedItemTile(item: item)
                    }
                }
                .frame(width: Self.itemWidth)
                .padding(.bottom, 4)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    if hasFolders, sidebar.shows(.folders) {
                        railDivider

                        ForEach(pinnedFolders) { folder in
                            SidebarFolderTileView(folder: folder, isCurrent: false) {
                                sidebar.openFolderIdentifier = folder.id
                                sidebar.isCompact = false
                            }
                        }

                        if showsTrash {
                            SidebarTrashTile()
                        }
                    }

                    railDivider

                    VStack(spacing: 0) {
                        ForEach(sidebar.shows(.openApps) ? otherOpenApps : []) { app in
                            SidebarRailItem(
                                help: app.localizedName,
                                isCurrent: workspace.frontmostBundleIdentifier == app.bundleIdentifier
                            ) {
                                workspace.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
                            } icon: {
                                SidebarAppIcon(bundleIdentifier: app.bundleIdentifier, size: SidebarRailMetrics.iconSize)
                            }
                        }
                        SidebarRailItem(help: "New Window", isQuiet: true) {
                            SidebarSearchController.shared.toggle(.apps)
                        } icon: {
                            plusSymbol
                        }

                        // "+" for a new tab stays even with no tab open.
                        if sidebar.shows(.tabs) {
                            railDivider
                                .padding(.vertical, 2)

                            ForEach(otherTabs) { tab in
                                SidebarRailItem(
                                    help: tab.title.isEmpty ? (tab.host ?? "Tab") : tab.title,
                                    isCurrent: tab.isActive && tab.isInFrontWindow
                                        && workspace.frontmostBundleIdentifier == BrowserTabsService.browserBundleIdentifier,
                                    hasBadge: DockyPreferences.shared.showsAppBadges && tab.unreadCount != nil
                                ) {
                                    BrowserTabsService.shared.focus(tab)
                                } icon: {
                                    SidebarWebIcon(url: tab.url, size: SidebarRailMetrics.iconSize)
                                }
                            }
                            SidebarRailItem(help: "New Tab", isQuiet: true) {
                                SidebarSearchController.shared.toggle(.web)
                            } icon: {
                                plusSymbol
                            }
                        }
                    }
                }
                .frame(width: Self.itemWidth)
                .padding(.bottom, 6)
            }
            .frame(minHeight: 60)

            if !widgets.isEmpty, sidebar.shows(.widgets) {
                railDivider
                    .padding(.bottom, 6)

                VStack(spacing: 4) {
                    ForEach(widgets, id: \.identifier) { widget in
                        SidebarWidgetItem(widget: widget, isRail: true)
                    }
                }
                .frame(width: Self.itemWidth)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private var hasFolders: Bool {
        !pinnedFolders.isEmpty || showsTrash
    }

    private var plusSymbol: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .light))
            .foregroundStyle(.secondary)
    }

    private var railDivider: some View {
        SidebarWave()
            .frame(width: 27)
            .padding(.vertical, 2)
    }
}

/// An open app or tab in the compact rail: a bare icon, smaller and closer
/// to its neighbours than the pinned tiles, with no resting background, so
/// what is pinned reads first and what is merely open stays light.
private enum SidebarRailMetrics {
    static let iconSize: CGFloat = 16
}

private struct SidebarRailItem<Icon: View>: View {
    let help: String
    var isCurrent = false
    var isQuiet = false
    /// Unread items: a red dot on the icon's corner.
    var hasBadge = false
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: SidebarRailMetrics.iconSize, height: SidebarRailMetrics.iconSize)
                .opacity(isQuiet && !isHovered ? 0.6 : 1)
                .overlay(alignment: .topTrailing) {
                    if hasBadge {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .offset(x: 3, y: -2)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(SidebarItemBackground(
                    isHovered: isHovered,
                    isCurrent: isCurrent,
                    cornerRadius: 7
                ))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Bottom bar

/// The bar along the bottom of the screen. Folded, it is the compact rail
/// laid on its side: the same tiles and bare icons, in a row. Unfolded, the
/// open apps and tabs become tabs, the way a browser lines up its tabs
/// along the top: an icon and a name each, sharing the width, the one in
/// front in the white pill, a close button under the pointer.
///
/// Room runs out the way it does on the Windows 11 taskbar and in browser
/// tab strips: the two ends never move (the Apple mark, the clock and the
/// toggle on the left; the widgets and "…" on the right), what is pinned
/// keeps its place, and the open apps and tabs share the rest. They shrink
/// to a minimum width, then whatever still does not fit goes behind a "»"
/// button that lists it, keeping the one in front always in view. Each
/// part can also be left out altogether from "…".
private struct SidebarBottomBar: View {
    let pinnedItems: [SidebarPinnedItem]
    let pinnedFolders: [SidebarPinnedFolder]
    let showsTrash: Bool
    let otherOpenApps: [RunningApp]
    let otherTabs: [BrowserTab]
    let widgets: [WidgetTile]

    @ObservedObject private var sidebar = SidebarPreferences.shared
    @State private var openFolder: SidebarPinnedFolder?

    private static let tileWidth: CGFloat = 40
    private static let widgetWidth: CGFloat = 150

    var body: some View {
        HStack(spacing: 4) {
            // Left end: always there.
            HStack(spacing: 4) {
                SidebarIconButton(
                    systemName: sidebar.isCompact ? "rectangle.bottomthird.inset.filled" : "rectangle.split.3x1",
                    help: sidebar.isCompact ? "Show names" : "Show icons only"
                ) {
                    sidebar.isCompact.toggle()
                }
            }
            .fixedSize()

            if showsPinned {
                SidebarBarDivider()
                pinned.fixedSize()
            }

            if showsFolders {
                SidebarBarDivider()
                folders.fixedSize()
            }

            SidebarBarDivider()

            // The shared part: shrinks, then overflows behind "»".
            SidebarBottomOpenItems(
                apps: sidebar.shows(.openApps) ? otherOpenApps : [],
                tabs: sidebar.shows(.tabs) ? otherTabs : [],
                isCompact: sidebar.isCompact,
                showsTabs: sidebar.shows(.tabs)
            )

            // Right end: always there.
            HStack(spacing: 4) {
                if !widgets.isEmpty, sidebar.shows(.widgets) {
                    SidebarBarDivider()
                    ForEach(widgets, id: \.identifier) { widget in
                        SidebarWidgetItem(widget: widget, isRail: sidebar.isCompact)
                            .frame(width: sidebar.isCompact ? Self.tileWidth : Self.widgetWidth)
                    }
                }
                SidebarOptionsMenu()
            }
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            // The edge that sets the bar apart from a window above it.
            Rectangle()
                .fill(Color.primary.opacity(0.18))
                .frame(height: 1)
        }
    }

    private var showsPinned: Bool {
        sidebar.shows(.pinned) && !pinnedItems.isEmpty
    }

    private var showsFolders: Bool {
        sidebar.shows(.folders) && (!pinnedFolders.isEmpty || showsTrash)
    }

    private var pinned: some View {
        HStack(spacing: SidebarMetrics.tileSpacing) {
            ForEach(pinnedItems) { item in
                SidebarPinnedItemTile(item: item)
                    .frame(width: Self.tileWidth)
            }
        }
    }

    /// A folder's contents open above its tile.
    private var folders: some View {
        HStack(spacing: SidebarMetrics.tileSpacing) {
            ForEach(pinnedFolders) { folder in
                SidebarFolderTileView(folder: folder, isCurrent: openFolder?.id == folder.id) {
                    openFolder = openFolder?.id == folder.id ? nil : folder
                }
                .frame(width: Self.tileWidth)
                .popover(isPresented: Binding(
                    get: { openFolder?.id == folder.id },
                    set: { if !$0 { openFolder = nil } }
                ), arrowEdge: .top) {
                    ScrollView {
                        SidebarFolderContents(folder: folder) { openFolder = nil }
                            .padding(8)
                    }
                    .frame(width: 240)
                    .frame(maxHeight: 420)
                }
            }
            if showsTrash {
                SidebarTrashTile()
                    .frame(width: Self.tileWidth)
            }
        }
    }
}

/// The wavy separator, stood on end.
private struct SidebarBarDivider: View {
    var body: some View {
        SidebarWave()
            .frame(width: 22)
            .rotationEffect(.degrees(90))
            .frame(width: 6, height: 22)
    }
}

private struct SidebarBarPlus: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .light))
            .foregroundStyle(.secondary)
    }
}

/// An open app or a tab, as the bottom bar shows it.
private enum SidebarOpenItem: Identifiable {
    case app(RunningApp)
    case tab(BrowserTab)

    var id: String {
        switch self {
        case .app(let app): "app-\(app.id)"
        case .tab(let tab): "tab-\(tab.id)"
        }
    }

    var isTab: Bool {
        if case .tab = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .app(let app): app.localizedName
        case .tab(let tab): tab.title.isEmpty ? (tab.host ?? "Tab") : tab.title
        }
    }

    func isCurrent(frontmost: String?) -> Bool {
        switch self {
        case .app(let app):
            frontmost == app.bundleIdentifier
        case .tab(let tab):
            tab.isActive && tab.isInFrontWindow && frontmost == BrowserTabsService.browserBundleIdentifier
        }
    }

    func activate() {
        switch self {
        case .app(let app): WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        case .tab(let tab): BrowserTabsService.shared.focus(tab)
        }
    }

    func close() {
        switch self {
        case .app(let app): WorkspaceService.shared.quit(bundleIdentifier: app.bundleIdentifier)
        case .tab(let tab): BrowserTabsService.shared.close(tab)
        }
    }

    var closeHelp: String { isTab ? "Close Tab" : "Quit" }

    /// Unread items, for a tab whose title carries a count.
    var unreadCount: String? {
        guard DockyPreferences.shared.showsAppBadges, case .tab(let tab) = self else { return nil }
        return tab.unreadCount
    }

    @ViewBuilder
    func icon(size: CGFloat) -> some View {
        switch self {
        case .app(let app): SidebarAppIcon(bundleIdentifier: app.bundleIdentifier, size: size)
        case .tab(let tab): SidebarWebIcon(url: tab.url, size: size)
        }
    }
}

/// The open apps, then Chrome's tabs, each group ending with "+". Folded
/// they are bare icons; unfolded, browser tabs that share the room between
/// a minimum and a maximum width. What does not fit goes behind "»".
private struct SidebarBottomOpenItems: View {
    let apps: [RunningApp]
    let tabs: [BrowserTab]
    let isCompact: Bool
    /// The tabs' part of the bar is on, with or without tabs open.
    let showsTabs: Bool

    @ObservedObject private var workspace = WorkspaceService.shared
    @State private var showsOverflow = false

    private static let iconWidth: CGFloat = 30
    private static let minimumWidth: CGFloat = 76
    private static let maximumWidth: CGFloat = 190
    private static let plusWidth: CGFloat = 28
    private static let overflowWidth: CGFloat = 40
    private static let spacing: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let layout = layout(available: geometry.size.width)
            HStack(spacing: Self.spacing) {
                ForEach(layout.visible.filter { !$0.isTab }) { item in
                    cell(item, width: layout.width)
                }
                plus(help: "New Window") { SidebarSearchController.shared.toggle(.apps) }

                // "+" for a new tab stays even with no tab open.
                if showsTabs {
                    SidebarBarDivider()
                    ForEach(layout.visible.filter(\.isTab)) { item in
                        cell(item, width: layout.width)
                    }
                    plus(help: "New Tab") { SidebarSearchController.shared.toggle(.web) }
                }

                if !layout.hidden.isEmpty {
                    overflowButton(layout.hidden)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private var items: [SidebarOpenItem] {
        apps.map(SidebarOpenItem.app) + tabs.map(SidebarOpenItem.tab)
    }

    /// How wide each item is, and which fit. When some do not, the one in
    /// front always stays in view, in place of the last that fits.
    private func layout(available: CGFloat) -> (width: CGFloat, visible: [SidebarOpenItem], hidden: [SidebarOpenItem]) {
        let all = items
        let pluses = CGFloat(showsTabs ? 2 : 1) * (Self.plusWidth + Self.spacing)
        let dividers: CGFloat = showsTabs ? 6 + Self.spacing : 0
        let room = available - pluses - dividers
        let count = CGFloat(all.count)
        guard count > 0 else { return (Self.maximumWidth, [], []) }

        let minimum = isCompact ? Self.iconWidth : Self.minimumWidth
        if count * (minimum + Self.spacing) <= room {
            let width = isCompact ? Self.iconWidth
                : min(Self.maximumWidth, max(Self.minimumWidth, room / count - Self.spacing))
            return (width, all, [])
        }

        let fitting = max(0, Int((room - Self.overflowWidth - Self.spacing) / (minimum + Self.spacing)))
        var visible = Array(all.prefix(fitting))
        var hidden = Array(all.dropFirst(fitting))
        let frontmost = workspace.frontmostBundleIdentifier
        if fitting > 0, let current = hidden.firstIndex(where: { $0.isCurrent(frontmost: frontmost) }) {
            let promoted = hidden.remove(at: current)
            hidden.insert(visible.removeLast(), at: 0)
            visible.append(promoted)
        }
        return (minimum, visible, hidden)
    }

    @ViewBuilder
    private func cell(_ item: SidebarOpenItem, width: CGFloat) -> some View {
        let isCurrent = item.isCurrent(frontmost: workspace.frontmostBundleIdentifier)
        if isCompact {
            SidebarRailItem(help: item.title, isCurrent: isCurrent, hasBadge: item.unreadCount != nil, action: item.activate) {
                item.icon(size: SidebarRailMetrics.iconSize)
            }
            .frame(width: width)
        } else {
            SidebarBottomTab(
                title: item.title,
                isCurrent: isCurrent,
                closeHelp: item.closeHelp,
                badge: item.unreadCount,
                action: item.activate,
                close: item.close
            ) {
                item.icon(size: 16)
            }
            .frame(width: width)
        }
    }

    private func plus(help: String, action: @escaping () -> Void) -> some View {
        SidebarRailItem(help: help, isQuiet: true, action: action) {
            SidebarBarPlus()
        }
        .frame(width: Self.plusWidth)
    }

    /// "» 5": the items that did not fit, as a list above the bar.
    private func overflowButton(_ hidden: [SidebarOpenItem]) -> some View {
        Button {
            showsOverflow.toggle()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(hidden.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(.secondary)
            .frame(width: Self.overflowWidth, height: 26)
            .background(SidebarItemBackground(isHovered: showsOverflow, isCurrent: false, restingOpacity: 0.05, cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(hidden.count) more")
        .popover(isPresented: $showsOverflow, arrowEdge: .top) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(hidden) { item in
                        SidebarBottomTab(
                            title: item.title,
                            isCurrent: item.isCurrent(frontmost: workspace.frontmostBundleIdentifier),
                            closeHelp: item.closeHelp,
                            badge: item.unreadCount,
                            action: {
                                showsOverflow = false
                                item.activate()
                            },
                            close: item.close
                        ) {
                            item.icon(size: 16)
                        }
                    }
                }
                .padding(6)
            }
            .frame(width: 260)
            .frame(maxHeight: 420)
        }
    }
}

/// One tab of the bottom bar: icon, name, and "×" under the pointer.
private struct SidebarBottomTab<Icon: View>: View {
    let title: String
    let isCurrent: Bool
    let closeHelp: String
    var badge: String?
    let action: () -> Void
    let close: () -> Void
    @ViewBuilder let icon: () -> Icon

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            icon()
                .frame(width: 16, height: 16)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isHovered {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(closeHelp)
            } else if let badge {
                SidebarBadge(text: badge)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(height: 32)
        .background(SidebarItemBackground(
            isHovered: isHovered,
            isCurrent: isCurrent,
            restingOpacity: 0.05,
            cornerRadius: 8
        ))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { isHovered = $0 }
        .help(title)
    }
}

// MARK: - Bottom-edge switcher

/// Down the left side, a panel of the open apps and tabs that comes up
/// when the pointer rests on the bottom edge of the screen, the way the
/// Dock and the Windows taskbar come up when hidden: click one to switch
/// to it. It goes away once the pointer leaves it, or after a switch.
/// The bar at the bottom already shows all this, so it never shows then.
final class SidebarSwitcherController {
    static let shared = SidebarSwitcherController()

    private let preferences = SidebarPreferences.shared
    private var panel: NSPanel?
    private var timer: Timer?
    private var edgeDwellStart: Date?
    private var awayStart: Date?
    private var activationObserver: NSObjectProtocol?

    private let revealDwell: TimeInterval = 0.15
    private let hideDelay: TimeInterval = 0.35
    private static let height: CGFloat = 96
    private static let margin: CGFloat = 8

    private init() {}

    /// Called with the sidebar: watches the bottom edge while it is on.
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        hide()
    }

    private var isShowing: Bool {
        panel?.isVisible == true
    }

    private func tick() {
        guard preferences.isEnabled, preferences.showsBottomSwitcher, !preferences.isBottom,
              !SidebarWindowController.shared.isSteppedAside,
              let screen = SidebarWindowController.shared.screen else {
            hide()
            return
        }
        let pointer = NSEvent.mouseLocation
        let now = Date()

        if isShowing, let panel {
            // A list opened from the panel ("»") counts as the panel.
            let onOwnWindow = NSApp.windows.contains { window in
                window.isVisible && window !== panel
                    && String(describing: type(of: window)).contains("Popover")
                    && window.frame.contains(pointer)
            }
            if panel.frame.insetBy(dx: -24, dy: -24).contains(pointer) || onOwnWindow || NSEvent.pressedMouseButtons != 0 {
                awayStart = nil
            } else if let start = awayStart {
                if now.timeIntervalSince(start) >= hideDelay { hide() }
            } else {
                awayStart = now
            }
            return
        }

        let edge = CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: 3)
        // Not on the sidebar's own stretch of the edge.
        let sidebarMaxX = SidebarWindowController.shared.panelMaxX ?? screen.frame.minX
        guard edge.contains(pointer), pointer.x > sidebarMaxX else {
            edgeDwellStart = nil
            return
        }
        if let start = edgeDwellStart {
            if now.timeIntervalSince(start) >= revealDwell {
                edgeDwellStart = nil
                show(on: screen)
            }
        } else {
            edgeDwellStart = now
        }
    }

    private func show(on screen: NSScreen) {
        let panel = panel ?? makePanel()
        self.panel = panel
        awayStart = nil

        // Wide enough for every item at its fullest, within the free part
        // of the screen; the items shrink and overflow inside it.
        let visible = screen.visibleFrame
        let left = SidebarWindowController.shared.panelMaxX ?? visible.minX
        let room = visible.maxX - left - Self.margin * 2
        let itemCount = CGFloat(WorkspaceService.shared.runningApps.count + (BrowserTabsService.shared.tabs?.count ?? 0))
        let width = min(room, max(200, itemCount * SidebarSwitcherView.cellWidth + 40))
        let frame = CGRect(
            x: left + (visible.maxX - left - width) / 2,
            y: screen.frame.minY + Self.margin,
            width: width,
            height: Self.height
        )
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        edgeDwellStart = nil
        awayStart = nil
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = SidebarSwitcherPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hostingView = SidebarSwitcherHostingView(rootView: SidebarSwitcherView())
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        return panel
    }
}

private final class SidebarSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SidebarSwitcherHostingView: NSHostingView<SidebarSwitcherView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Every open app, then every tab, as large icons, like the Dock; the name
/// shows on hover. A click switches to it. Nothing else happens here.
private struct SidebarSwitcherView: View {
    static let cellWidth: CGFloat = 80
    private static let iconSize: CGFloat = 64

    @ObservedObject private var workspace = WorkspaceService.shared
    @ObservedObject private var browserTabs = BrowserTabsService.shared
    @Bindable private var preferences = DockyPreferences.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(items) { item in
                    SidebarSwitcherCell(
                        item: item,
                        isCurrent: item.isCurrent(frontmost: workspace.frontmostBundleIdentifier),
                        iconSize: Self.iconSize
                    )
                    .frame(width: Self.cellWidth)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SidebarPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
    }

    /// Chrome steps aside while its tabs are listed one by one.
    private var items: [SidebarOpenItem] {
        let tabs = browserTabs.tabs ?? []
        let apps = workspace.runningApps.filter { app in
            !preferences.isAppHiddenInDocky(bundleIdentifier: app.bundleIdentifier)
                && !(!tabs.isEmpty && app.bundleIdentifier == BrowserTabsService.browserBundleIdentifier)
        }
        return apps.map(SidebarOpenItem.app) + tabs.map(SidebarOpenItem.tab)
    }
}

private struct SidebarSwitcherCell: View {
    let item: SidebarOpenItem
    let isCurrent: Bool
    let iconSize: CGFloat

    @State private var isHovered = false

    var body: some View {
        item.icon(size: iconSize)
            .frame(width: iconSize, height: iconSize)
            .overlay(alignment: .topTrailing) {
                if let badge = item.unreadCount {
                    SidebarBadge(text: badge)
                        .offset(x: 5, y: -4)
                }
            }
            .padding(8)
        .frame(maxWidth: .infinity)
        .background(SidebarItemBackground(isHovered: isHovered, isCurrent: isCurrent, cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { item.activate() }
        .onHover { isHovered = $0 }
        .help(item.title)
    }
}

// MARK: - Wallpaper

/// The desktop picture in the theme's colors: the same gradient as the bar,
/// top to bottom, so the menu bar (which shows the desktop through it) and
/// the desktop around the windows carry on from the bar. Made for each
/// screen's size when the theme changes; the person's own picture is kept
/// and put back for the Claude theme or when the option is turned off.
enum SidebarWallpaper {
    private static let savedKey = "docky.fork.sidebar.savedWallpapers"

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Docky/Wallpapers", isDirectory: true)
    }

    static func apply(_ theme: SidebarTheme, enabled: Bool) {
        guard enabled, !theme.isClaude else {
            restore()
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        saveOriginalsIfNeeded()
        for screen in NSScreen.screens {
            let size = CGSize(
                width: screen.frame.width * screen.backingScaleFactor,
                height: screen.frame.height * screen.backingScaleFactor
            )
            let url = folder.appendingPathComponent("\(theme.id)-\(theme.isDark ? "dark" : "light")-\(Int(size.width))x\(Int(size.height)).png")
            if !FileManager.default.fileExists(atPath: url.path) {
                guard render(theme, size: size, to: url) else { continue }
            }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    /// The person's own pictures, saved once before the first themed one.
    private static func saveOriginalsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.dictionary(forKey: savedKey) == nil else { return }
        var saved: [String: String] = [:]
        for screen in NSScreen.screens {
            if let url = NSWorkspace.shared.desktopImageURL(for: screen), !url.path.hasPrefix(folder.path) {
                saved[screen.localizedName] = url.path
            }
        }
        defaults.set(saved, forKey: savedKey)
    }

    private static func restore() {
        let defaults = UserDefaults.standard
        guard let saved = defaults.dictionary(forKey: savedKey) as? [String: String] else { return }
        for screen in NSScreen.screens {
            if let path = saved[screen.localizedName] ?? saved.values.first {
                try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
            }
        }
        defaults.removeObject(forKey: savedKey)
    }

    private static func render(_ theme: SidebarTheme, size: CGSize, to url: URL) -> Bool {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        func color(_ hex: Int) -> CGColor {
            CGColor(colorSpace: space, components: [
                CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, 1,
            ])!
        }
        // Core Graphics counts from the bottom: the top color goes at the top.
        let gradient = CGGradient(colorsSpace: space, colors: [color(theme.bottom), color(theme.top)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return false }
        return (try? data.write(to: url)) != nil
    }
}

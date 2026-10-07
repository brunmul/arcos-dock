//
//  SidebarView.swift
//  Docky
//
//  Content of the sidebar. It follows the layout of Arc's sidebar, top to
//  bottom:
//
//    header      the Apple mark, the full / compact toggle, and a menu
//                (auto-hide, settings, back to the dock strip); then the
//                greeting, the date and the time (`SidebarWelcome.swift`)
//    pinned      two small blocks of tiles: the pinned apps, then the
//                pinned folders and the Trash. A folder's tile lists its
//                contents underneath
//    open        every open app; a row unfolds into the app's windows.
//                "New Window" closes the list and opens the app search
//    widgets     the dock's widgets as rows the size of an app's row;
//                their detail opens beside the sidebar on hover
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
    @Bindable private var preferences = DockyPreferences.shared

    private static let horizontalPadding: CGFloat = 8

    var body: some View {
        Group {
            if sidebar.isCompact {
                SidebarRail(
                    pinnedApps: pinnedApps,
                    pinnedFolders: pinnedFolders,
                    showsTrash: showsTrash,
                    otherOpenApps: unpinnedOpenApps,
                    widgets: widgets
                )
            } else {
                fullSidebar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SidebarChrome())
    }

    private var fullSidebar: some View {
        VStack(spacing: 0) {
            SidebarHeader()
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.top, 8)

            SidebarWelcome()
                .padding(.horizontal, Self.horizontalPadding + 4)
                .padding(.top, 8)
                .padding(.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    pinnedSection

                    SidebarDivider()
                        .padding(.vertical, 6)

                    openSection
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.bottom, 6)
            }
            .frame(minHeight: 80)

            if !widgets.isEmpty {
                SidebarDivider()
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.bottom, 6)

                VStack(spacing: 2) {
                    ForEach(widgets, id: \.identifier) { widget in
                        SidebarWidgetItem(widget: widget)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
            }
        }
        .padding(.bottom, 8)
    }

    /// Everything pinned to the dock, as two small blocks of tiles: the
    /// apps, then the folders and the Trash. The folder whose tile is
    /// selected lists its contents underneath.
    @ViewBuilder
    private var pinnedSection: some View {
        if !pinnedApps.isEmpty {
            SidebarFavoritesGrid(apps: pinnedApps)
        }

        if !pinnedFolders.isEmpty || showsTrash {
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
            .padding(.top, pinnedApps.isEmpty ? 0 : 7)
        }

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
        ForEach(openApps) { app in
            SidebarOpenAppSection(
                app: app,
                windows: windowRegistry.windows(forBundleIdentifier: app.bundleIdentifier)
            )
        }

        SidebarActionRow(systemName: "plus", title: "New Window", isQuiet: true) {
            sidebarOpenAppSearch()
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

    /// Every running app, oldest first, minus the ones hidden from Docky.
    private var openApps: [RunningApp] {
        workspace.runningApps.filter { app in
            !preferences.isAppHiddenInDocky(bundleIdentifier: app.bundleIdentifier)
        }
    }

    /// Open apps that are not pinned. The compact rail lists these under
    /// the pinned ones, so no icon shows up twice.
    private var unpinnedOpenApps: [RunningApp] {
        let pinned = Set(pinnedApps.map(\.bundleIdentifier))
        return openApps.filter { !pinned.contains($0.bundleIdentifier) }
    }

    private var widgets: [WidgetTile] {
        var result: [WidgetTile] = []
        for tile in tileStore.tiles {
            if case .widget(let widget) = tile.content, widget.kind != .calendarDate {
                result.append(widget)
            }
        }
        return result
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
        tileStore.tiles.contains { tile in
            if case .trash = tile.content {
                return true
            }
            return false
        }
    }
}

// MARK: - Chrome

/// The sidebar's surface: opaque warm paper (see `SidebarPalette`).
/// Opaque on purpose: the sidebar is meant to read as part of the screen's
/// frame, not as glass floating over the desktop.
struct SidebarChrome: View {
    var body: some View {
        SidebarPalette.surface
    }
}

/// The two concave corners drawn just right of the sidebar, at the top and
/// the bottom, in the sidebar's own surface. They round off the area next
/// to the sidebar so the windows there look set into it.
struct SidebarCornersView: View {
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
            // around both corners, on the window's side of them.
            SidebarEdgeOutline()
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                .padding(.leading, 0.5)
        }
        .allowsHitTesting(false)
    }

    private func corner(isTop: Bool) -> some View {
        SidebarChrome()
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

private struct SidebarHeader: View {
    @ObservedObject private var sidebar = SidebarPreferences.shared

    var body: some View {
        HStack(spacing: 2) {
            SidebarAppleMark()

            Spacer(minLength: 0)

            SidebarIconButton(systemName: "sidebar.left", help: "Show icons only") {
                sidebar.isCompact = true
            }

            Menu {
                Toggle("Hide Automatically", isOn: Binding(
                    get: { !sidebar.isPinned },
                    set: { sidebar.isPinned = !$0 }
                ))
                Divider()
                Button("Settings…") {
                    (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
                }
                Button("Switch to Dock") {
                    SidebarWindowController.shared.setSidebarMode(false)
                }
                Divider()
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
        .frame(height: 24)
    }
}

private struct SidebarDivider: View {
    var body: some View {
        SidebarWave()
            .padding(.horizontal, 4)
    }
}

// MARK: - Compact rail

/// The sidebar reduced to a column of icons. Pinned apps, pinned folders,
/// the other open apps, "+", and the widgets as icon tiles. Clicking a
/// folder opens the full sidebar on it.
private struct SidebarRail: View {
    let pinnedApps: [AppTile]
    let pinnedFolders: [SidebarPinnedFolder]
    let showsTrash: Bool
    let otherOpenApps: [RunningApp]
    let widgets: [WidgetTile]

    @ObservedObject private var sidebar = SidebarPreferences.shared

    private static let itemWidth: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            SidebarAppleMark()
                .padding(.top, 8)

            SidebarRailClock()
                .padding(.top, 2)
                .padding(.bottom, 6)

            SidebarIconButton(systemName: "sidebar.left", help: "Show the full sidebar") {
                sidebar.isCompact = false
            }
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(pinnedApps, id: \.bundleIdentifier) { app in
                        SidebarAppTile(app: app)
                    }

                    if hasFolders {
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

                    ForEach(otherOpenApps) { app in
                        SidebarAppTile(app: AppTile(
                            bundleIdentifier: app.bundleIdentifier,
                            displayName: app.localizedName
                        ))
                    }

                    SidebarSymbolTile(systemName: "plus", help: "New Window", restingOpacity: 0) {
                        sidebarOpenAppSearch()
                    }
                }
                .frame(width: Self.itemWidth)
                .padding(.bottom, 6)
            }
            .frame(minHeight: 60)

            if !widgets.isEmpty {
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

    private var railDivider: some View {
        SidebarWave()
            .frame(width: 27)
            .padding(.vertical, 2)
    }
}

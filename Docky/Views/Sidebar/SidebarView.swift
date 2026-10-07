//
//  SidebarView.swift
//  Docky
//
//  Content of the sidebar, top to bottom:
//
//    header      pin / unpin, and a menu (settings, back to the dock strip)
//    favorites   the pinned apps, as a grid of icons
//    list        app folders, then every open app; an app row unfolds
//                into its windows
//    widgets     the dock's widgets at full width; each unfolds in place
//                into the detailed view the dock shows on hover
//    footer      pinned folders and the Trash
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
    @Bindable private var preferences = DockyPreferences.shared

    private static let cornerRadius: CGFloat = 18
    private static let horizontalPadding: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader()
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.top, 8)

            if !favoriteApps.isEmpty {
                SidebarFavoritesGrid(apps: favoriteApps)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 6)
            }

            sectionDivider

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(appFolders, id: \.identifier) { folder in
                        SidebarFolderSection(folder: folder)
                    }

                    if !appFolders.isEmpty, !openApps.isEmpty {
                        SidebarSectionLabel(title: "Open")
                            .padding(.top, 8)
                    }

                    ForEach(openApps) { app in
                        SidebarOpenAppSection(
                            app: app,
                            windows: windowRegistry.windows(forBundleIdentifier: app.bundleIdentifier)
                        )
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 80)

            if !widgets.isEmpty {
                sectionDivider

                VStack(spacing: 6) {
                    ForEach(widgets, id: \.identifier) { widget in
                        SidebarWidgetRow(widget: widget)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
            }

            SidebarFooter(folders: pinnedFolders, showsTrash: showsTrash)
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dockyWidgetGlass(cornerRadius: Self.cornerRadius)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 1)
            .padding(.horizontal, Self.horizontalPadding + 2)
            .padding(.vertical, 8)
    }

    // MARK: - Data

    /// Apps pinned to the dock, in dock order.
    private var favoriteApps: [AppTile] {
        var apps: [AppTile] = []
        for tile in tileStore.tiles where tile.id.hasPrefix("pinned:") {
            if case .app(let app) = tile.content, !app.bundleIdentifier.isEmpty {
                apps.append(app)
            }
        }
        return apps
    }

    private var appFolders: [AppFolderTile] {
        var folders: [AppFolderTile] = []
        for tile in tileStore.tiles {
            if case .appFolder(let folder) = tile.content {
                folders.append(folder)
            }
        }
        return folders
    }

    /// Every running app, oldest first, minus the ones hidden from Docky.
    private var openApps: [RunningApp] {
        workspace.runningApps.filter { app in
            !preferences.isAppHiddenInDocky(bundleIdentifier: app.bundleIdentifier)
        }
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

    private var pinnedFolders: [FolderTile] {
        var folders: [FolderTile] = []
        for tile in tileStore.tiles {
            if case .folder(let folder) = tile.content {
                folders.append(folder)
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

// MARK: - Header and footer

private struct SidebarHeader: View {
    @ObservedObject private var sidebar = SidebarPreferences.shared

    var body: some View {
        HStack(spacing: 6) {
            SidebarIconButton(
                systemName: sidebar.isPinned ? "sidebar.left" : "sidebar.squares.left",
                help: sidebar.isPinned ? "Hide the sidebar until the pointer reaches the left edge" : "Keep the sidebar on screen"
            ) {
                sidebar.isPinned.toggle()
            }

            Spacer(minLength: 0)

            Menu {
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 24)
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

private struct SidebarFooter: View {
    let folders: [FolderTile]
    let showsTrash: Bool

    @ObservedObject private var trash = TrashService.shared

    var body: some View {
        HStack(spacing: 6) {
            ForEach(folders, id: \.url) { folder in
                SidebarFolderChip(folder: folder)
            }

            Spacer(minLength: 0)

            if showsTrash {
                Button {
                    let trashURL = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".Trash", isDirectory: true)
                    NSWorkspace.shared.open(trashURL)
                } label: {
                    Image(nsImage: NSImage(named: trash.isEmpty ? "NSTrashEmpty" : "NSTrashFull") ?? NSImage())
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Trash")
            }
        }
        .frame(height: 26)
    }
}

/// A pinned folder, opened in Finder on click. Drawn with a symbol and
/// the folder's name rather than its real icon: asking the system for the
/// icon of Downloads or Documents makes macOS prompt for access to that
/// folder, and the prompt would hold up the whole sidebar at launch.
private struct SidebarFolderChip: View {
    let folder: FolderTile

    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(folder.url)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(folder.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.14 : 0.07))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open \(folder.displayName) in Finder")
    }
}

// MARK: - Widgets

/// One widget at full sidebar width. The chevron unfolds it in place into
/// the detailed view the dock strip shows in its hover panel.
private struct SidebarWidgetRow: View {
    let widget: WidgetTile

    @ObservedObject private var sidebar = SidebarPreferences.shared

    private var isExpanded: Bool {
        sidebar.expandedWidgetIdentifiers.contains(widget.identifier)
    }

    private var canExpand: Bool {
        widget.kind.isExpandable
    }

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            WidgetTileView(
                tile: widget,
                cornerRadius: 12,
                renderedSpan: .four,
                isWithinStack: false,
                isExpanded: isExpanded,
                isExpandedPreviewOpen: isExpanded
            )
            .frame(height: isExpanded ? expandedHeight : collapsedHeight)
            .onTapGesture {
                // Folded, the whole widget is the target. Unfolded, only
                // the chevron folds it back, so a click inside the detail
                // view never closes it by accident.
                guard canExpand, !isExpanded else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    sidebar.toggleWidget(widget.identifier)
                }
            }

            if canExpand {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        sidebar.toggleWidget(widget.identifier)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: collapsedHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Show less" : "Show more")
            }
        }
    }

    private var collapsedHeight: CGFloat {
        52
    }

    private var expandedHeight: CGFloat {
        switch widget.kind {
        case .calendar:
            280
        case .nowPlaying:
            150
        case .systemStatus:
            210
        default:
            230
        }
    }
}

// MARK: - Small shared pieces

struct SidebarSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.6)
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SidebarIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 24)
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

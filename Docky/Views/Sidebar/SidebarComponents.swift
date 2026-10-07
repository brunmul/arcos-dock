//
//  SidebarComponents.swift
//  Docky
//
//  The app-related pieces of the sidebar: the favorites grid, the foldable
//  app folders, and the open apps that unfold into their windows. Layout
//  and data wiring live in `SidebarView`.
//

import AppKit
import SwiftUI

// MARK: - Shared

/// An app's icon, honoring the custom icon the user picked for it.
struct SidebarAppIcon: View {
    let bundleIdentifier: String
    let size: CGFloat

    @Bindable private var preferences = DockyPreferences.shared

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    private var image: NSImage {
        if let overrideURL = preferences.effectiveAppIconOverrideURL(forBundleIdentifier: bundleIdentifier),
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }
        return IconCacheService.shared.icon(forBundleIdentifier: bundleIdentifier)
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
    return injectingCustomIconActions(into: withWindows, for: app)
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
            .padding(.horizontal, 5)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(Color.red))
    }
}

/// Hover and "current" background shared by every row and grid cell.
private struct SidebarRowBackground: View {
    let isHovered: Bool
    let isCurrent: Bool
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(opacity))
    }

    private var opacity: Double {
        if isCurrent {
            return isHovered ? 0.2 : 0.14
        }
        return isHovered ? 0.08 : 0
    }
}

private let sidebarRowHeight: CGFloat = 30
private let sidebarFoldAnimation = Animation.spring(response: 0.28, dampingFraction: 0.86)

// MARK: - Favorites

/// Pinned apps as a grid of icons, like the favorites at the top of Arc's
/// sidebar. A dot marks the ones that are running.
struct SidebarFavoritesGrid: View {
    let apps: [AppTile]

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 40), spacing: 6),
        count: 4
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(apps, id: \.bundleIdentifier) { app in
                SidebarFavoriteCell(app: app)
            }
        }
    }
}

private struct SidebarFavoriteCell: View {
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

    var body: some View {
        Button {
            workspace.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        } label: {
            VStack(spacing: 2) {
                SidebarAppIcon(bundleIdentifier: app.bundleIdentifier, size: 34)
                    .scaleEffect(isHovered ? 1.06 : 1)

                Circle()
                    .fill(Color.primary.opacity(isRunning ? 0.55 : 0))
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(SidebarRowBackground(isHovered: isHovered, isCurrent: isFrontmost, cornerRadius: 11))
            .overlay(alignment: .topTrailing) {
                if preferences.showsAppBadges, let badge = badges.badge(forBundleIdentifier: app.bundleIdentifier) {
                    SidebarBadge(text: badge)
                        .padding(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
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

// MARK: - App folders

/// An app folder as a foldable group: a header row, then one row per app.
struct SidebarFolderSection: View {
    let folder: AppFolderTile

    @ObservedObject private var sidebar = SidebarPreferences.shared
    @State private var isHeaderHovered = false

    private var isOpen: Bool {
        !sidebar.collapsedFolderIdentifiers.contains(folder.identifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                withAnimation(sidebarFoldAnimation) {
                    sidebar.toggleFolder(folder.identifier)
                }
            } label: {
                HStack(spacing: 6) {
                    SidebarChevron(isOpen: isOpen)

                    Image(systemName: isOpen ? "folder" : "folder.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    Text(folder.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(folder.apps.count)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .frame(height: sidebarRowHeight)
                .background(SidebarRowBackground(isHovered: isHeaderHovered, isCurrent: false))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHeaderHovered = $0 }

            if isOpen {
                ForEach(folder.apps, id: \.bundleIdentifier) { app in
                    SidebarFolderAppRow(app: app)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
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
            HStack(spacing: 8) {
                SidebarAppIcon(bundleIdentifier: app.bundleIdentifier, size: 20)

                Text(app.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isRunning {
                    Circle()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.leading, 26)
            .padding(.trailing, 8)
            .frame(height: sidebarRowHeight)
            .background(SidebarRowBackground(
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

// MARK: - Open apps

/// One open app, the sidebar's "tab". Clicking the row brings the app
/// forward; the chevron unfolds its windows underneath.
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
        HStack(spacing: 6) {
            foldButton

            SidebarAppIcon(bundleIdentifier: app.bundleIdentifier, size: 20)
                .opacity(app.isHidden ? 0.5 : 1)

            Text(app.localizedName)
                .font(.system(size: 13, weight: isFrontmost ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            trailing
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .frame(height: sidebarRowHeight)
        .background(SidebarRowBackground(isHovered: isHovered, isCurrent: isFrontmost))
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
    }

    /// The chevron, or an empty slot of the same width for an app without
    /// windows so the icons stay aligned.
    @ViewBuilder
    private var foldButton: some View {
        if windows.isEmpty {
            Color.clear.frame(width: 14, height: sidebarRowHeight)
        } else {
            Button {
                withAnimation(sidebarFoldAnimation) {
                    sidebar.toggleExpansion(ofApp: app.bundleIdentifier)
                }
            } label: {
                SidebarChevron(isOpen: isOpen)
                    .frame(height: sidebarRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Hide windows" : "Show windows")
        }
    }

    /// Quit button while hovering, otherwise the unread badge or the
    /// window count.
    @ViewBuilder
    private var trailing: some View {
        if isHovered {
            SidebarRowCloseButton(help: "Quit \(app.localizedName)") {
                workspace.quit(bundleIdentifier: app.bundleIdentifier)
            }
        } else if preferences.showsAppBadges, let badge = badges.badge(forBundleIdentifier: app.bundleIdentifier) {
            SidebarBadge(text: badge)
        } else if windows.count > 1 {
            Text("\(windows.count)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .padding(.trailing, 4)
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
            Image(systemName: window.isMinimized ? "minus.rectangle" : "macwindow")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(window.isMinimized ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if isHovered {
                SidebarRowCloseButton(help: "Close window") {
                    _ = WorkspaceService.shared.close(window: window)
                }
            }
        }
        .padding(.leading, 30)
        .padding(.trailing, 6)
        .frame(height: 26)
        .background(SidebarRowBackground(isHovered: isHovered, isCurrent: false, cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture {
            _ = WorkspaceService.shared.focus(window: window)
        }
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Small controls

private struct SidebarChevron: View {
    let isOpen: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isOpen ? 90 : 0))
            .frame(width: 14)
    }
}

private struct SidebarRowCloseButton: View {
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.14 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

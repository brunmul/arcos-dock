//
//  SidebarSettingsView.swift
//  Docky
//
//  The sidebar's options, gathered in Settings in four panes: Layout,
//  Appearance, Content and Widgets. Every choice is shown as what it does
//  rather than named: a small drawing of the screen for the position, the
//  theme's own colors for a theme, tiles or rows for a layout. Switches
//  carry a line saying what they change. The sidebar's "…" menu only
//  leads here.
//

import AppKit
import SwiftUI

enum SidebarSettingsPane {
    case layout, appearance, content, widgets
}

struct SidebarSettingsView: View {
    let pane: SidebarSettingsPane

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                switch pane {
                case .layout: SidebarLayoutSettings()
                case .appearance: SidebarAppearanceSettings()
                case .content: SidebarContentSettings()
                case .widgets: SidebarWidgetsSettings()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Layout

private struct SidebarLayoutSettings: View {
    @ObservedObject private var sidebar = SidebarPreferences.shared

    var body: some View {
        SettingsGroup(title: "Position", note: "Where the bar sits on the screen.") {
            HStack(spacing: 12) {
                ChoiceCard(title: "Left", isSelected: sidebar.edge == .left) {
                    ScreenSketch(edge: .left, isCompact: false)
                } action: { sidebar.edge = .left }
                ChoiceCard(title: "Bottom", isSelected: sidebar.edge == .bottom) {
                    ScreenSketch(edge: .bottom, isCompact: false)
                } action: { sidebar.edge = .bottom }
            }
        }

        SettingsGroup(title: "Form", note: "Names and widgets, or icons only.") {
            HStack(spacing: 12) {
                ChoiceCard(title: "Full", isSelected: !sidebar.isCompact) {
                    ScreenSketch(edge: sidebar.edge, isCompact: false)
                } action: { sidebar.isCompact = false }
                ChoiceCard(title: "Icons Only", isSelected: sidebar.isCompact) {
                    ScreenSketch(edge: sidebar.edge, isCompact: true)
                } action: { sidebar.isCompact = true }
            }
        }

        SettingsGroup(
            title: "Width",
            note: "Width of the full bar down the left. The pinned tiles fill as many columns as it holds."
        ) {
            HStack(spacing: 12) {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(.secondary)
                Slider(
                    value: $sidebar.fullWidth,
                    in: SidebarPreferences.fullWidthRange,
                    step: 10
                )
                Text("\(Int(sidebar.fullWidth)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
                Button("Reset") {
                    sidebar.fullWidth = SidebarPreferences.defaultFullWidth
                }
                .disabled(sidebar.fullWidth == SidebarPreferences.defaultFullWidth)
            }
            .padding(14)
            .settingsCard()
            .disabled(sidebar.isBottom || sidebar.isCompact)
        }

        SettingsGroup(title: "Behavior") {
            VStack(spacing: 0) {
                ToggleRow(
                    symbol: "eye.slash",
                    title: "Hide Automatically",
                    note: "The bar steps away and comes back when the pointer rests on the screen's edge.",
                    isOn: Binding(get: { !sidebar.isPinned }, set: { sidebar.isPinned = !$0 })
                )
                Divider().padding(.leading, 44)
                ToggleRow(
                    symbol: "rectangle.bottomthird.inset.filled",
                    title: "Open Apps Panel at Bottom Edge",
                    note: "Resting the pointer on the bottom of the screen shows the open apps.",
                    isOn: $sidebar.showsBottomSwitcher
                )
                .disabled(sidebar.isBottom)
            }
            .settingsCard()
        }

        SettingsGroup(title: "Dock") {
            HStack {
                Label("Go back to the dock strip, Docky's original form.", systemImage: "dock.rectangle")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Switch to Dock") {
                    SidebarWindowController.shared.setSidebarMode(false)
                }
            }
            .padding(14)
            .settingsCard()
        }
    }
}

// MARK: - Appearance

private struct SidebarAppearanceSettings: View {
    @ObservedObject private var sidebar = SidebarPreferences.shared

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        SettingsGroup(title: "Theme", note: "The bar's colors. Claude follows the system's light or dark mode.") {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(SidebarTheme.all) { theme in
                    ChoiceCard(title: theme.name, isSelected: sidebar.themeID == theme.id) {
                        ThemeSketch(theme: theme)
                    } action: { sidebar.themeID = theme.id }
                }
            }
        }

        SettingsGroup(title: "Wallpaper") {
            ToggleRow(
                symbol: "photo.on.rectangle",
                title: "Match Wallpaper to Theme",
                note: "The desktop picture takes the theme's colors; your own comes back when this is off.",
                isOn: $sidebar.matchesWallpaper
            )
            .settingsCard()
        }

        SettingsGroup(title: "Icons", note: "In order: your icon pack, the site's icon, a tinted symbol, the full icon.") {
            VStack(spacing: 0) {
                ToggleRow(
                    symbol: "globe",
                    title: "Website Icons",
                    note: "An app shows the icon its website uses in a browser tab, when one is found.",
                    isOn: $sidebar.usesWebsiteIcons
                )
                Divider().padding(.leading, 44)
                ToggleRow(
                    symbol: "circle.lefthalf.filled",
                    title: "Tinted Icons",
                    note: "Icons drawn in one color, without their plate.",
                    isOn: $sidebar.usesTintedIcons
                )
                Divider().padding(.leading, 44)
                ButtonRow(
                    symbol: "folder",
                    title: "Icon Pack",
                    note: "Drop images named after an app's bundle identifier in this folder.",
                    buttonTitle: "Open Folder"
                ) {
                    SidebarIconPack.shared.revealInFinder()
                }
            }
            .settingsCard()
        }
    }
}

// MARK: - Content

private struct SidebarContentSettings: View {
    @ObservedObject private var sidebar = SidebarPreferences.shared

    var body: some View {
        SettingsGroup(
            title: "Top",
            note: "Pinned apps and sites, and any widget moved up. Right-click an item to move it."
        ) {
            layoutChoice($sidebar.topLayout)
        }

        SettingsGroup(
            title: "Bottom",
            note: "The widgets, and any pinned app or site moved down."
        ) {
            layoutChoice($sidebar.bottomLayout)
        }

        SettingsGroup(title: "Lists") {
            VStack(spacing: 0) {
                ToggleRow(
                    symbol: "square.on.square",
                    title: "Pinned Items Also in Apps & Web",
                    note: "A pinned app that is open, or a pinned site with a tab, also has its row in the lists.",
                    isOn: $sidebar.showsPinnedAppsInOpenList
                )
                Divider().padding(.leading, 44)
                ToggleRow(
                    symbol: "trash",
                    title: "Show Trash",
                    note: "The Trash as a tile among the pinned folders.",
                    isOn: $sidebar.showsTrash
                )
                Divider().padding(.leading, 44)
                ButtonRow(
                    symbol: "folder.badge.plus",
                    title: "Pinned Folders",
                    note: "A pinned folder lists its contents under the tiles.",
                    buttonTitle: "Pin a Folder…"
                ) {
                    sidebarPinFolder()
                }
            }
            .settingsCard()
        }

        SettingsGroup(title: "Icons Only & Bottom Bar", note: "What the smaller forms of the bar keep.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    CheckTile(
                        symbol: section.symbolName,
                        title: section.title,
                        isOn: Binding(
                            get: { sidebar.shows(section) },
                            set: { sidebar.setShows(section, $0) }
                        )
                    )
                }
            }
        }
    }

    private func layoutChoice(_ selection: Binding<SidebarLayout>) -> some View {
        HStack(spacing: 12) {
            ForEach(SidebarLayout.allCases, id: \.self) { layout in
                ChoiceCard(title: layout.title, isSelected: selection.wrappedValue == layout) {
                    LayoutSketch(layout: layout)
                } action: { selection.wrappedValue = layout }
            }
        }
    }
}

// MARK: - Widgets

private struct SidebarWidgetsSettings: View {
    @ObservedObject private var sidebar = SidebarPreferences.shared
    @ObservedObject private var tileStore = TileStore.shared

    var body: some View {
        SettingsGroup(
            title: "Widgets",
            note: "Those shown in the bar, and where. A widget removed with a right-click comes back here."
        ) {
            VStack(spacing: 0) {
                let widgets = SidebarPreferences.allWidgets(in: tileStore)
                ForEach(Array(widgets.enumerated()), id: \.element.identifier) { index, widget in
                    if index > 0 {
                        Divider().padding(.leading, 44)
                    }
                    HStack(spacing: 12) {
                        SettingsSymbol(symbol: widget.kind.sidebarSymbolName)
                        Text(widget.title)
                        Spacer(minLength: 12)
                        Picker("", selection: Binding(
                            get: { sidebar.place(of: widget) },
                            set: { sidebar.move(widget, to: $0) }
                        )) {
                            Text("Top").tag(SidebarPlace.top)
                            Text("Bottom").tag(SidebarPlace.bottom)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 130)
                        .disabled(!sidebar.shows(widget: widget))
                        Toggle("", isOn: Binding(
                            get: { sidebar.shows(widget: widget) },
                            set: { sidebar.setShows(widget: widget, $0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .settingsCard()
        }
    }
}

// MARK: - Pieces

/// A titled block of options, with a line saying what it is about.
private struct SettingsGroup<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
    }
}

private extension View {
    func settingsCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// One choice among a few, shown as a drawing of its result with its name
/// under it; the chosen one is ringed in the accent color.
private struct ChoiceCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    @ViewBuilder let preview: () -> Preview
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                preview()
                    .frame(height: 74)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.25 : 0.12),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(title)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A switch with a symbol, its name and what it does.
private struct ToggleRow: View {
    let symbol: String
    let title: String
    let note: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsSymbol(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Like `ToggleRow`, with a button in place of the switch.
private struct ButtonRow: View {
    let symbol: String
    let title: String
    let note: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsSymbol(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(buttonTitle, action: action)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A tile that is on or off, for a set of things to keep: its symbol and
/// name, ticked when on.
private struct CheckTile: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// An option's symbol, in outline on a soft square, the way the sidebar
/// draws its folders.
private struct SettingsSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}

// MARK: - Sketches

/// A screen with the bar on it, as the position and form choices draw it.
private struct ScreenSketch: View {
    let edge: SidebarEdge
    let isCompact: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                Color.primary.opacity(0.06)

                if edge == .left {
                    let width = isCompact ? size.width * 0.09 : size.width * 0.28
                    barFill
                        .frame(width: width, height: size.height)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<5, id: \.self) { index in
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.35))
                                    .frame(width: 6, height: 6)
                                if !isCompact {
                                    RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.18))
                                        .frame(width: width * (index.isMultiple(of: 2) ? 0.5 : 0.35), height: 4)
                                }
                            }
                        }
                    }
                    .padding(6)
                    window
                        .frame(width: size.width - width - 12, height: size.height - 14)
                        .offset(x: width + 6, y: 7)
                } else {
                    let height = isCompact ? size.height * 0.16 : size.height * 0.24
                    window
                        .frame(width: size.width - 14, height: size.height - height - 12)
                        .offset(x: 7, y: 6)
                    barFill
                        .frame(width: size.width, height: height)
                        .offset(y: size.height - height)
                    HStack(spacing: 4) {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.35))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(width: size.width, height: height)
                    .offset(y: size.height - height)
                }
            }
        }
    }

    private var barFill: some View {
        Rectangle().fill(SidebarPalette.surface)
            .overlay(Rectangle().fill(Color.primary.opacity(0.05)))
    }

    private var window: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
    }
}

/// A theme as a small bar in its colors beside a window.
private struct ThemeSketch: View {
    let theme: SidebarTheme

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<4, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(ink.opacity(index == 1 ? 0.55 : 0.28))
                                .frame(width: size.width * (index == 1 ? 0.22 : 0.17), height: 4)
                        }
                    }
                    .padding(7)
                }
                .frame(width: size.width * 0.38)
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    private var isDark: Bool {
        theme.isClaude ? colorScheme == .dark : theme.isDark
    }

    private var ink: Color { isDark ? .white : .black }

    private var top: Color {
        theme.isClaude ? SidebarPalette.surface : Self.color(theme.top)
    }

    private var bottom: Color {
        theme.isClaude ? SidebarPalette.surface : Self.color(theme.bottom)
    }

    private static func color(_ hex: Int) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Tiles or rows, as a place of the bar draws its items.
private struct LayoutSketch: View {
    let layout: SidebarLayout

    var body: some View {
        ZStack {
            SidebarPalette.surface
            switch layout {
            case .grid:
                VStack(spacing: 5) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: 5) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(width: 20, height: 18)
                                    .overlay(
                                        Circle().fill(Color.primary.opacity(0.35)).frame(width: 7, height: 7)
                                    )
                            }
                        }
                    }
                }
            case .list:
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        HStack(spacing: 6) {
                            Circle().fill(Color.primary.opacity(0.35)).frame(width: 7, height: 7)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.primary.opacity(0.2))
                                .frame(width: index.isMultiple(of: 2) ? 60 : 44, height: 4)
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.primary.opacity(0.12))
                                .frame(width: 14, height: 4)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Symbols

extension SidebarSection {
    var symbolName: String {
        switch self {
        case .pinned: "pin"
        case .folders: "folder"
        case .openApps: "macwindow"
        case .tabs: "globe"
        case .widgets: "square.grid.2x2"
        }
    }
}

extension WidgetKind {
    /// The symbol the settings list shows beside a widget.
    var sidebarSymbolName: String {
        switch self {
        case .calendar, .calendarDate: "calendar"
        case .nowPlaying: "music.note"
        case .systemStatus: "cpu"
        case .claudeActivity: "sparkle"
        case .reminders: "checklist"
        case .batteries: "battery.75percent"
        case .weather: "cloud.sun"
        case .search: "magnifyingglass"
        case .photoFrame: "photo"
        case .external: "square.grid.2x2"
        }
    }
}

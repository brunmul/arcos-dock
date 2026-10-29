//
//  BehaviorSettingsView.swift
//  Docky
//

import SwiftUI

struct BehaviorSettingsView: View {
    enum Subsection {
        case general
        case placement
        case visibility
        case appTileClick
        case widgets
        case launch
        case systemDock
        case appFolders
    }

    let subsection: Subsection

    @Bindable private var preferences = DockyPreferences.shared
    @State private var isShowingResetConfirmation = false

    var body: some View {
        SettingsPage {
            switch subsection {
            case .general:
                generalSection
            case .placement:
                placementSection
            case .visibility:
                visibilitySection
            case .appTileClick:
                appTileClickSection
            case .widgets:
                widgetsSection
            case .launch:
                launchSection
            case .systemDock:
                systemDockSection
            case .appFolders:
                appFoldersSection
            }
        }
        .confirmationDialog(
            "Reset behavior settings?",
            isPresented: $isShowingResetConfirmation
        ) {
            Button("Reset Behavior", role: .destructive) {
                DockyPreferences.shared.resetBehaviorToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Placement, visibility, app-tile click, app folders, widgets, launch, and system-dock settings will return to their defaults. Appearance, app icons, and other settings are unaffected. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var generalSection: some View {
        SettingsGroup(title: "Reset", note: "Every behavior setting back to its built-in default.") {
            SettingsCard {
                ButtonRow(
                    symbol: "arrow.counterclockwise",
                    title: "Reset Behavior Settings",
                    note: "Placement, visibility, app-tile click, app folders, widgets, launch and system Dock. Useful when a theme has nudged behavior somewhere you want to undo.",
                    buttonTitle: "Reset to Defaults"
                ) {
                    isShowingResetConfirmation = true
                }
            }
        }
    }

    @ViewBuilder
    private var placementSection: some View {
        SettingsGroup(title: "Position", note: "Where the dock strip sits, or the same edge as the macOS Dock.") {
            HStack(spacing: 12) {
                ForEach(DockWindowPosition.allCases) { position in
                    ChoiceCard(title: position.title, isSelected: preferences.windowPosition == position) {
                        DockStripSketch(position: position)
                    } action: { preferences.windowPosition = position }
                }
            }
        }

        SettingsGroup(title: "Screens") {
            SettingsCard {
                PickerRow(
                    symbol: "display.2",
                    title: "Display",
                    note: "Stay on the primary display, or follow the display the pointer is on.",
                    selection: $preferences.windowDisplayTarget,
                    isSegmented: true
                ) {
                    ForEach(DockWindowDisplayTarget.allCases) { Text($0.title).tag($0) }
                }
                SettingsDivider()
                PickerRow(
                    symbol: "square.on.square",
                    title: "Spaces",
                    note: "Only the active Space, or every Space including full-screen ones.",
                    selection: $preferences.windowSpaceBehavior,
                    isSegmented: true
                ) {
                    ForEach(DockWindowSpaceBehavior.allCases) { Text($0.title).tag($0) }
                }
            }
        }
    }

    @ViewBuilder
    private var visibilitySection: some View {
        SettingsGroup(title: "Hiding", note: "When the dock steps out of the way.") {
            SettingsCard {
                ToggleRow(
                    symbol: "eye.slash",
                    title: "Autohide Window",
                    note: "Slides off-screen until the pointer reaches its edge.",
                    isOn: $preferences.autohidesWindow
                )
                SettingsDivider()
                SliderRow(
                    symbol: "timer",
                    title: "Autohide Delay",
                    note: "How long it waits after the pointer leaves before hiding.",
                    value: $preferences.autohideWindowDelay,
                    range: 0...5
                )
                .disabled(!preferences.autohidesWindow)
                SettingsDivider()
                SliderRow(
                    symbol: "wind",
                    title: "Animation Duration",
                    note: "How long the slide takes. 0 snaps instantly.",
                    value: $preferences.autohideAnimationDuration,
                    range: 0...1
                )
                .disabled(!preferences.autohidesWindow)
                SettingsDivider()
                ToggleRow(
                    symbol: "arrow.up.left.and.arrow.down.right",
                    title: "Hide in Fullscreen",
                    note: "Autohides while a full-screen app is on its display; off, it stays over them.",
                    isOn: $preferences.hidesDuringFullscreen
                )
                SettingsDivider()
                SliderRow(
                    symbol: "hourglass",
                    title: "Fullscreen Reveal Delay",
                    note: "How long the pointer must rest on the edge to bring it back over a full-screen app.",
                    value: $preferences.fullscreenRevealDelay,
                    range: 0...2
                )
                .disabled(!preferences.hidesDuringFullscreen)
            }
        }

        SettingsGroup(title: "Size and Windows") {
            SettingsCard {
                PickerRow(
                    symbol: "macwindow",
                    title: "Maximized Windows",
                    note: preferences.maximizedWindowBehavior.detail,
                    selection: $preferences.maximizedWindowBehavior
                ) {
                    ForEach(MaximizedWindowBehavior.allCases) { Text($0.title).tag($0) }
                }
                SettingsDivider()
                PickerRow(
                    symbol: "arrow.left.and.right.square",
                    title: "Overflow",
                    note: "Shrink to fit the screen, or keep the size and scroll.",
                    selection: $preferences.overflowBehavior,
                    isSegmented: true
                ) {
                    ForEach(DockOverflowBehavior.allCases) { Text($0.title).tag($0) }
                }
                SettingsDivider()
                PickerRow(
                    symbol: "arrow.left.and.line.vertical.and.arrow.right",
                    title: "Window Axis Size",
                    note: "Hug the tiles, or stretch across the whole edge.",
                    selection: $preferences.windowAxisSizing,
                    isSegmented: true
                ) {
                    ForEach(DockWindowAxisSizing.allCases) { Text($0.title).tag($0) }
                }
            }
        }

        SettingsGroup(title: "Apps Shown") {
            SettingsCard {
                ToggleRow(
                    symbol: "app.badge.checkmark",
                    title: "Show Running Apps",
                    note: "Off, unpinned running apps are hidden and the dock is a static shelf.",
                    isOn: $preferences.showsRunningApps
                )
                SettingsDivider()
                ToggleRow(
                    symbol: "line.diagonal",
                    title: "Show Active/Pinned Separator",
                    note: "Off, running apps join the pinned ones as a single strip.",
                    isOn: $preferences.showsActivePinnedSeparator
                )
                .disabled(!preferences.showsRunningApps)
                SettingsDivider()
                ToggleRow(
                    symbol: "clock.arrow.circlepath",
                    title: "Disable Recent Apps",
                    note: "Keeps the layout stable as apps launch, even with running apps shown.",
                    isOn: $preferences.hidesRecentApps
                )
                SettingsDivider()
                ToggleRow(
                    symbol: "circle.lefthalf.filled",
                    title: "Dim Idle App Icons",
                    note: "Half opacity while an app is hidden or has no window. Needs Accessibility.",
                    isOn: $preferences.dimsIdleAppIcons
                )
            }
        }

        SettingsGroup(title: "Badges") {
            SettingsCard {
                ToggleRow(
                    symbol: "app.badge",
                    title: "Show Notification Badges",
                    note: "The red count, like Mail's unread total, read from the system Dock. Needs Accessibility.",
                    isOn: $preferences.showsAppBadges
                )
                SettingsDivider()
                PickerRow(
                    symbol: "folder.badge.plus",
                    title: "Folder Badges",
                    note: "One total on the folder, or a badge on each app in it.",
                    selection: $preferences.folderBadgeMode,
                    isSegmented: true
                ) {
                    ForEach(FolderBadgeMode.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!preferences.showsAppBadges)
                SettingsDivider()
                PickerRow(
                    symbol: "smallcircle.filled.circle",
                    title: "Per-App Badge Style",
                    note: "A dot or the full count on the folder's preview. The open folder always shows the count.",
                    selection: $preferences.folderBadgePreviewStyle,
                    isSegmented: true
                ) {
                    ForEach(FolderBadgePreviewStyle.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!preferences.showsAppBadges || preferences.folderBadgeMode != .perApp)
            }
        }

        SettingsGroup(title: "Shelve Mode", note: "The dock as a shelf of pinned apps and widgets.") {
            SettingsCard {
                ToggleRow(
                    symbol: "books.vertical",
                    title: "Shelve Mode",
                    note: "Hides the fixtures picked below.",
                    isOn: $preferences.enablesShelveMode
                )
                SettingsDivider()
                ToggleRow(
                    symbol: "face.smiling",
                    title: "Hide Finder",
                    note: "No Finder tile while shelve mode is on.",
                    isOn: $preferences.shelveHidesFinder
                )
                .disabled(!preferences.enablesShelveMode)
                SettingsDivider()
                ToggleRow(
                    symbol: "trash",
                    title: "Hide Trash",
                    note: "No Trash tile while shelve mode is on.",
                    isOn: $preferences.shelveHidesTrash
                )
                .disabled(!preferences.enablesShelveMode)
            }
        }

        SettingsGroup(title: "Minimized Windows") {
            SettingsCard {
                ToggleRow(
                    symbol: "dock.arrow.down.rectangle",
                    title: "Show Minimized Windows",
                    note: "Minimized windows as tiles at the end of the dock.",
                    isOn: $preferences.showsMinimizedWindows
                )
                SettingsDivider()
                ToggleRow(
                    symbol: "rectangle.stack",
                    title: "List in Switcher & Previews",
                    note: "Minimized windows in the window switcher and hover previews, dimmed and labeled.",
                    isOn: $preferences.includesMinimizedWindows
                )
            }
        }
    }

    @ViewBuilder
    private var appTileClickSection: some View {
        SettingsGroup(
            title: "When the App Is Already in Front",
            note: "Clicking an app that is not in front always opens, focuses or restores it."
        ) {
            SettingsCard {
                PickerRow(
                    symbol: "cursorarrow.click",
                    title: "Click Action",
                    note: "What a click on the tile of the app in front does.",
                    selection: frontmostClickBehaviorBinding
                ) {
                    ForEach(AppTileFrontmostClickBehavior.allCases) { Text(frontmostClickBehaviorTitle($0)).tag($0) }
                }
            }
        }
    }

    @ViewBuilder
    private var widgetsSection: some View {
        SettingsGroup(title: "Hover Preview", note: "A larger view of a widget while the pointer rests on it.") {
            SettingsCard {
                ToggleRow(
                    symbol: "arrow.up.left.and.arrow.down.right",
                    title: "Show Expanded Preview on Hover",
                    note: "Off, widgets stay at their pinned size.",
                    isOn: $preferences.enablesWidgetHoverPreview
                )
                SettingsDivider()
                SliderRow(
                    symbol: "timer",
                    title: "Hover Preview Delay",
                    note: "How long the pointer rests before the preview opens.",
                    value: $preferences.widgetHoverPreviewDelay,
                    range: 0...2,
                    format: { $0 == 0 ? "Off" : String(format: "%.2f s", $0) }
                )
                .disabled(!preferences.enablesWidgetHoverPreview)
            }
        }

        SettingsGroup(title: "Apply to Sizes", note: "Which widget sizes open the preview.") {
            HStack(spacing: 10) {
                // `.four` is theme-only; skip it in the user-facing
                // hover-preview span toggles.
                ForEach(TileSpan.allCases.filter { $0 != .four }) { span in
                    CheckTile(symbol: spanSymbol(for: span), title: spanTitle(for: span), isOn: spanBinding(for: span))
                }
            }
            .disabled(!preferences.enablesWidgetHoverPreview)
        }
    }

    @ViewBuilder
    private var launchSection: some View {
        SettingsGroup(title: "Launch") {
            SettingsCard {
                ToggleRow(
                    symbol: "power",
                    title: "Open at Login",
                    note: "Oriel starts by itself after you sign in.",
                    isOn: $preferences.opensAtLogin
                )
            }
        }
    }

    @ViewBuilder
    private var systemDockSection: some View {
        SettingsGroup(
            title: "System Dock",
            note: "Oriel saves your Dock settings first and puts them back when this is off or Oriel quits."
        ) {
            SettingsCard {
                ToggleRow(
                    symbol: "dock.rectangle",
                    title: "Hide System Dock",
                    note: "The macOS Dock autohides with a long delay, without bouncing or launch animations, on Oriel's edge.",
                    isOn: $preferences.hidesSystemDock
                )
                SettingsDivider()
                ButtonRow(
                    symbol: "arrow.uturn.backward",
                    title: "Restore System Dock",
                    note: "Brings the macOS Dock back as it was.",
                    buttonTitle: "Restore"
                ) {
                    preferences.hidesSystemDock = false
                }
                .disabled(!preferences.hidesSystemDock)
            }
        }
    }

    @ViewBuilder
    private var appFoldersSection: some View {
        SettingsGroup(title: "App Folders") {
            SettingsCard {
                ToggleRow(
                    symbol: "folder",
                    title: "Group Opened Apps Beside Their Folder",
                    note: "A folder's running apps sit right after it, and the folder shows how many are open.",
                    isOn: $preferences.showsGroupedOpenedAppsInDock
                )
                SettingsDivider()
                ToggleRow(
                    symbol: "rectangle.roundedtop",
                    title: "Grouping Backdrop",
                    note: "A rounded backdrop around the folder and its opened apps.",
                    isOn: $preferences.showsGroupedOpenedAppsBackdrop
                )
                .disabled(!preferences.showsGroupedOpenedAppsInDock)
            }
        }
    }

    private func spanSymbol(for span: TileSpan) -> String {
        switch span {
        case .one: "square"
        case .two: "rectangle"
        case .three, .four: "rectangle.portrait"
        }
    }

    private func spanTitle(for span: TileSpan) -> String {
        switch span {
        case .one: "Small"
        case .two: "Medium"
        case .three: "Large"
        case .four: "Extra Large"
        }
    }

    private var frontmostClickBehaviorBinding: Binding<AppTileFrontmostClickBehavior> {
        Binding(
            get: { preferences.appTileFrontmostClickBehavior },
            set: { newValue in
                preferences.appTileFrontmostClickBehavior = newValue
            }
        )
    }

    private func frontmostClickBehaviorTitle(_ behavior: AppTileFrontmostClickBehavior) -> String {
        behavior.title
    }

    private func spanBinding(for span: TileSpan) -> Binding<Bool> {
        Binding(
            get: { preferences.widgetHoverPreviewSpans.contains(span) },
            set: { isOn in
                var spans = preferences.widgetHoverPreviewSpans
                if isOn {
                    spans.insert(span)
                } else {
                    spans.remove(span)
                }
                preferences.widgetHoverPreviewSpans = spans
            }
        )
    }
}

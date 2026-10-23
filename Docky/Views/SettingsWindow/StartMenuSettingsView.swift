//
//  StartMenuSettingsView.swift
//  Docky
//

import SwiftUI

struct StartMenuSettingsView: View {
    @Bindable private var preferences = DockyPreferences.shared

    var body: some View {
        SettingsPage {
            SettingsBlockSection("Availability") {
                Toggle("Enable Start Menu", isOn: $preferences.enablesStartMenuOverlay)
                    .font(.headline)
                Text("Toggles the ⌃⌥S hotkey, the Start menu widget in the dock editor palette, and the Finder tile override below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SettingsBlockSection("Finder Tile") {
                Toggle("Open Start Menu from Finder tile", isOn: $preferences.opensStartMenuFromFinderTile)
                    .disabled(!preferences.enablesStartMenuOverlay)
                Text("When on, clicking the Finder tile opens the Start menu instead of activating Finder. Right-click still surfaces Finder's normal actions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

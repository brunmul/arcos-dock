//
//  ActionCatalogSettingsView.swift
//  Docky
//

import SwiftUI

struct ActionCatalogSettingsView: View {
    @ObservedObject private var catalog = MenuCatalogService.shared

    var body: some View {
        SettingsPage {
            SettingsBlockSection("About Actions") {
                Text("Actions are menu items Oriel injects into each tile's right-click menu. A catalog package ships a curated bundle of them; once it's loaded, every action it defines is automatically available on the matching tile type. Apps, folders, the Trash, the Launchpad, and the divider all get their own set, with no per-tile setup needed.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Action kinds Oriel will execute: built-in commands, AppleScript, and macOS menu-bar clicks. The first time an app-targeted AppleScript or menu-click action runs, macOS may prompt for Automation permission.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsBlockSection("Catalog Packages") {
                if catalog.packageSummaries.isEmpty {
                    Text("No catalog packages loaded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(catalog.packageSummaries) { package in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(package.title)
                                    .font(.headline)
                                Spacer()
                                Text(package.version)
                                    .foregroundStyle(.secondary)
                            }

                            Text("by \(package.author) • \(package.actionCount) actions • \(package.reviewStatus)")
                                .foregroundStyle(.secondary)

                            if let description = package.description {
                                Text(description)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            SettingsBlockSection("Scripted Actions") {
                Text("Oriel loads action definitions from bundled JSON. Future curated packages can add actions and append menu items at approved insertion points without replacing Oriel's core menus.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("Catalog Refresh")
                        .font(.headline)

                    Spacer()

                    Button("Reload Catalog") {
                        catalog.reload()
                    }
                }
            }

            if !catalog.diagnostics.isEmpty {
                SettingsBlockSection("Diagnostics") {
                    ForEach(Array(catalog.diagnostics.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

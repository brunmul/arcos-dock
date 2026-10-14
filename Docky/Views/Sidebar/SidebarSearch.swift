//
//  SidebarSearch.swift
//  Docky
//
//  What "New Window" (under the apps) and "New Tab" (under the web) open:
//  a search field, the way Arc's new-tab bar takes a site or a search.
//  The first looks through the apps, the second through Chrome's open
//  tabs and the web. Type, then Return:
//
//    - an app (installed or running) comes forward or launches;
//    - an open tab comes to the front;
//    - a Chrome bookmark opens in a new tab (`SidebarBookmarks`);
//    - an address opens in a new Chrome tab, anything else as a Google
//      search there.
//
//  The sidebar's own panel never takes the keyboard, so the field lives in
//  a small panel of its own, centered over the screen. It closes on
//  Escape, on a choice, or as soon as another window takes the keyboard.
//

import AppKit
import SwiftUI

/// What a search looks through: "New Window" under the apps searches the
/// apps, "New Tab" under the web searches the tabs and the web.
enum SidebarSearchScope {
    case apps
    case web
}

final class SidebarSearchController: NSObject {
    static let shared = SidebarSearchController()

    private var panel: SidebarSearchPanel?
    private static let size = CGSize(width: 540, height: 400)

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle(_ scope: SidebarSearchScope = .web) {
        isVisible ? hide() : show(scope)
    }

    func show(_ scope: SidebarSearchScope = .web) {
        let panel = panel ?? makePanel()
        self.panel = panel

        // A fresh field every time, like a new tab.
        let hostingView = NSHostingView(rootView: SidebarSearchView(scope: scope) { [weak self] in
            self?.hide()
        })
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        if let screen = SidebarWindowController.shared.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let sidebarMaxX = SidebarWindowController.shared.panelMaxX ?? visible.minX
            let midX = (sidebarMaxX + visible.maxX) / 2
            panel.setFrame(
                CGRect(
                    x: midX - Self.size.width / 2,
                    y: visible.maxY - visible.height * 0.22 - Self.size.height,
                    width: Self.size.width,
                    height: Self.size.height
                ),
                display: true
            )
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private func makePanel() -> SidebarSearchPanel {
        let panel = SidebarSearchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
        return panel
    }

    @objc private func panelDidResignKey(_ notification: Notification) {
        hide()
    }
}

/// Takes the keyboard without bringing Docky forward, like Spotlight.
private final class SidebarSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Results

enum SidebarSearchResult: Identifiable {
    case tab(BrowserTab)
    case bookmark(SidebarBookmark)
    case app(SidebarInstalledApp)
    case web(URL, isAddress: Bool, text: String)
    case allApps

    var id: String {
        switch self {
        case .tab(let tab): return "tab-\(tab.id)"
        case .bookmark(let bookmark): return "bookmark-\(bookmark.url.absoluteString)"
        case .app(let app): return "app-\(app.url.path)"
        case .web(let url, _, _): return "web-\(url.absoluteString)"
        case .allApps: return "all-apps"
        }
    }

    var kindKey: String {
        switch self {
        case .tab: "tab"
        case .bookmark: "bookmark"
        case .app: "app"
        case .web: "web"
        case .allApps: "all"
        }
    }

    func perform() {
        switch self {
        case .tab(let tab):
            BrowserTabsService.shared.focus(tab)
        case .app(let app):
            if let bundleIdentifier = app.bundleIdentifier {
                WorkspaceService.shared.activateOrOpen(bundleIdentifier: bundleIdentifier)
            } else {
                NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
            }
        case .bookmark(let bookmark):
            BrowserTabsService.shared.open(bookmark.url)
        case .web(let url, _, _):
            BrowserTabsService.shared.open(url)
        case .allApps:
            sidebarOpenAppSearch()
        }
    }
}

struct SidebarInstalledApp: Hashable {
    let name: String
    let url: URL
    let bundleIdentifier: String?
}

/// The apps in the usual folders, read once, off the main thread.
final class SidebarInstalledApps {
    static let shared = SidebarInstalledApps()

    private(set) var apps: [SidebarInstalledApp] = []
    private var isLoaded = false

    func loadIfNeeded(then completion: @escaping () -> Void) {
        guard !isLoaded else {
            completion()
            return
        }
        isLoaded = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.scan()
            DispatchQueue.main.async {
                self.apps = found
                completion()
            }
        }
    }

    private static func scan() -> [SidebarInstalledApp] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var result: [SidebarInstalledApp] = []
        var seen: Set<String> = []

        func visit(_ directory: URL, depth: Int) {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for entry in entries {
                if entry.pathExtension == "app" {
                    let bundleIdentifier = Bundle(url: entry)?.bundleIdentifier
                    let key = bundleIdentifier ?? entry.path
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    var name = fileManager.displayName(atPath: entry.path)
                    if name.hasSuffix(".app") {
                        name = String(name.dropLast(4))
                    }
                    result.append(SidebarInstalledApp(name: name, url: entry, bundleIdentifier: bundleIdentifier))
                } else if depth > 0,
                          (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    visit(entry, depth: depth - 1)
                }
            }
        }

        for root in roots {
            visit(root, depth: 2)
        }
        return result
    }
}

private enum SidebarSearchMatcher {
    static func results(
        for query: String,
        scope: SidebarSearchScope,
        tabs allTabs: [BrowserTab],
        bookmarks allBookmarks: [SidebarBookmark] = [],
        apps allApps: [SidebarInstalledApp]
    ) -> [SidebarSearchResult] {
        let tabs = scope == .web ? allTabs : []
        let apps = scope == .apps ? allApps : []
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            // Nothing typed yet: the open tabs to jump back to one, or the
            // way to every app.
            return scope == .web ? tabs.prefix(6).map { .tab($0) } : [.allApps]
        }

        let needle = normalized(text)
        var scored: [(score: Int, result: SidebarSearchResult)] = []

        for tab in tabs {
            let score = max(self.score(tab.title, needle), self.score(tab.host ?? "", needle))
            if score > 0 {
                scored.append((score * 10 + 3, .tab(tab)))
            }
        }
        if scope == .web {
            // A bookmark already open in a tab is offered as that tab.
            let openPages = Set(tabs.compactMap { $0.url?.absoluteString })
            for bookmark in allBookmarks where !openPages.contains(bookmark.url.absoluteString) {
                let score = max(self.score(bookmark.title, needle), self.score(bookmark.host ?? "", needle))
                if score > 0 {
                    scored.append((score * 10 + 2, .bookmark(bookmark)))
                }
            }
        }
        for app in apps {
            let score = self.score(app.name, needle)
            if score > 0 {
                scored.append((score * 10 + 2, .app(app)))
            }
        }

        // Each kind keeps some room: many open Google tabs must not push a
        // matching bookmark out of the list.
        var perKind: [String: Int] = [:]
        let matches = scored
            .sorted { $0.score > $1.score }
            .filter { entry in
                let kind = entry.result.kindKey
                perKind[kind, default: 0] += 1
                return perKind[kind]! <= (kind == "bookmark" ? 3 : 4)
            }
            .prefix(7)
            .map(\.result)

        guard scope == .web else {
            return matches.isEmpty ? [.allApps] : matches
        }

        let web = webResult(for: text)
        let hasStrongMatch = scored.contains { $0.score >= 20 }
        guard case .web(_, let isAddress, _) = web, isAddress || !hasStrongMatch else {
            return matches + [web]
        }
        return [web] + matches
    }

    /// 3 when the text starts with the query, 2 when every word of the
    /// query starts a word of the text ("google drive" in "Mon Drive -
    /// Google Drive", "drive" in "drive.google.com"), 1 when it merely
    /// contains each of them, 0 otherwise.
    private static func score(_ candidate: String, _ needle: String) -> Int {
        let haystack = normalized(candidate)
        if haystack.hasPrefix(needle) {
            return 3
        }
        let words = haystack.split { !$0.isLetter && !$0.isNumber }
        let parts = needle.split { !$0.isLetter && !$0.isNumber }
        guard !parts.isEmpty, parts.allSatisfy({ haystack.contains($0) }) else { return 0 }
        let allStartWords = parts.allSatisfy { part in words.contains { $0.hasPrefix(part) } }
        return allStartWords ? 2 : 1
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// An address when the text reads as one (no spaces, a dot before a
    /// plausible ending, or a scheme), otherwise a Google search.
    static func webResult(for text: String) -> SidebarSearchResult {
        if !text.contains(" ") {
            if text.contains("://"), let url = URL(string: text) {
                return .web(url, isAddress: true, text: text)
            }
            let host = text.split(separator: "/").first.map(String.init) ?? text
            let parts = host.split(separator: ".")
            let isLocal = host.hasPrefix("localhost")
            if isLocal || (parts.count >= 2 && (parts.last?.count ?? 0) >= 2 && parts.last?.allSatisfy(\.isLetter) == true),
               let url = URL(string: (isLocal ? "http://" : "https://") + text) {
                return .web(url, isAddress: true, text: text)
            }
        }

        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return .web(components.url!, isAddress: false, text: text)
    }
}

// MARK: - View

struct SidebarSearchView: View {
    let scope: SidebarSearchScope
    let dismiss: () -> Void

    @ObservedObject private var browserTabs = BrowserTabsService.shared
    @State private var query = ""
    @State private var selection = 0
    @State private var apps: [SidebarInstalledApp] = SidebarInstalledApps.shared.apps
    @State private var bookmarks: [SidebarBookmark] = SidebarBookmarks.shared.bookmarks
    @FocusState private var isFieldFocused: Bool

    private var results: [SidebarSearchResult] {
        SidebarSearchMatcher.results(
            for: query,
            scope: scope,
            tabs: browserTabs.tabs ?? [],
            bookmarks: scope == .web ? bookmarks : [],
            apps: apps
        )
    }

    var body: some View {
        let results = results
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(scope == .apps ? "Open an app" : "Search or enter address", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($isFieldFocused)
                    .onSubmit { perform(results, at: selection) }
                    .onKeyPress(.downArrow) {
                        selection = min(selection + 1, max(results.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selection = max(selection - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        dismiss()
                        return .handled
                    }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)

            if !results.isEmpty {
                SidebarWave()
                    .padding(.horizontal, 12)

                VStack(spacing: 1) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        SidebarSearchRow(result: result, isSelected: index == selection)
                            .contentShape(Rectangle())
                            .onTapGesture { perform(results, at: index) }
                            .onHover { if $0 { selection = index } }
                    }
                }
                .padding(6)
            }
        }
        .background(shape.fill(SidebarPalette.surface))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: query) { selection = 0 }
        .onAppear {
            isFieldFocused = true
            SidebarInstalledApps.shared.loadIfNeeded {
                apps = SidebarInstalledApps.shared.apps
            }
            if scope == .web {
                SidebarBookmarks.shared.refreshIfChanged {
                    bookmarks = SidebarBookmarks.shared.bookmarks
                }
            }
        }
    }

    private func perform(_ results: [SidebarSearchResult], at index: Int) {
        guard results.indices.contains(index) else { return }
        dismiss()
        results[index].perform()
    }
}

private struct SidebarSearchRow: View {
    let result: SidebarSearchResult
    let isSelected: Bool

    @ObservedObject private var favicons = SidebarFaviconStore.shared

    private static let ink = Color.primary.opacity(0.74)
    private static let iconSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: Self.iconSize, height: Self.iconSize)

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(kind)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.07 : 0))
        )
    }

    private var title: String {
        switch result {
        case .tab(let tab):
            let trimmed = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? (tab.host ?? "Tab") : trimmed
        case .bookmark(let bookmark):
            return bookmark.title.isEmpty ? (bookmark.host ?? bookmark.url.absoluteString) : bookmark.title
        case .app(let app):
            return app.name
        case .web(let url, let isAddress, let text):
            return isAddress ? url.absoluteString : "Search Google for “\(text)”"
        case .allApps:
            return "Show All Apps"
        }
    }

    private var kind: String {
        switch result {
        case .tab: return "Tab"
        case .bookmark: return "Bookmark"
        case .app: return "App"
        case .web(_, let isAddress, _): return isAddress ? "Open" : "Search"
        case .allApps: return ""
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch result {
        case .tab(let tab):
            SidebarWebIcon(url: tab.url, size: Self.iconSize)
        case .bookmark(let bookmark):
            SidebarWebIcon(url: bookmark.url, size: Self.iconSize)
        case .app(let app):
            if let bundleIdentifier = app.bundleIdentifier {
                SidebarAppIcon(bundleIdentifier: bundleIdentifier, size: Self.iconSize)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
            }
        case .web(_, let isAddress, _):
            SidebarAppSymbolView(
                systemName: isAddress ? "globe" : "magnifyingglass",
                tint: Self.ink,
                size: Self.iconSize
            )
        case .allApps:
            SidebarAppSymbolView(systemName: "square.grid.3x3", tint: Self.ink, size: Self.iconSize)
        }
    }
}

// MARK: - Bookmarks

struct SidebarBookmark: Hashable {
    let title: String
    let url: URL

    /// The site, without "www.", matched as well as the title: "google"
    /// finds a bookmark on drive.google.com.
    var host: String? { SidebarPinnedSite.host(of: url) }
}

/// Chrome's bookmarks, for New Tab's suggestions. Read from the small file
/// Chrome keeps them in, for every profile, and read again only when that
/// file has changed: opening New Tab costs a glance at its date. Like
/// Chrome's icons, it depends on macOS letting Docky read other apps'
/// data; while it may not, there are simply no bookmarks to offer.
final class SidebarBookmarks {
    static let shared = SidebarBookmarks()

    private(set) var bookmarks: [SidebarBookmark] = []
    private var readDates: [String: Date] = [:]
    private let queue = DispatchQueue(label: "gt.quintero.Docky.chrome-bookmarks", qos: .userInitiated)

    /// Read once ahead, so the first New Tab already has them.
    private init() {
        refreshIfChanged {}
    }

    func refreshIfChanged(then completion: @escaping () -> Void) {
        queue.async {
            let files = Self.bookmarkFiles()
            let dates = files.reduce(into: [String: Date]()) { result, file in
                result[file.path] = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
            }
            guard dates != self.readDates else { return }

            var seen: Set<String> = []
            var found: [SidebarBookmark] = []
            for file in files {
                guard let data = try? Data(contentsOf: file),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let roots = root["roots"] as? [String: Any] else { continue }
                for case let node as [String: Any] in roots.values {
                    Self.collect(node, into: &found, seen: &seen)
                }
            }
            DispatchQueue.main.async {
                self.readDates = dates
                self.bookmarks = found
                completion()
            }
        }
    }

    private static func bookmarkFiles() -> [URL] {
        // "Bookmarks" holds the ones kept on this Mac; "AccountBookmarks",
        // the ones of the Google account Chrome is signed in to, which
        // recent Chrome keeps apart (same format). Dia keeps the same files.
        SupportedBrowser.profileDirectories()
            .flatMap { profile in
                ["Bookmarks", "AccountBookmarks"].map { profile.appendingPathComponent($0) }
            }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func collect(_ node: [String: Any], into found: inout [SidebarBookmark], seen: inout Set<String>) {
        if node["type"] as? String == "url",
           let address = node["url"] as? String,
           let url = URL(string: address),
           url.scheme?.hasPrefix("http") == true,
           seen.insert(address).inserted {
            found.append(SidebarBookmark(title: node["name"] as? String ?? "", url: url))
        }
        for case let child as [String: Any] in node["children"] as? [Any] ?? [] {
            collect(child, into: &found, seen: &seen)
        }
    }
}

//
//  BrowserTabsService.swift
//  Docky
//
//  The open tabs of Chrome, so the sidebar can list them among the apps,
//  each site as its own row, the way Arc mixes them.
//
//  Chrome answers AppleScript: the list of its windows and their tabs,
//  which tab is active, and commands to switch to a tab or close it. The
//  list is read again every 1.5 s while Chrome runs, a few bulk requests
//  per window rather than several per tab; the first read asks
//  macOS whether Docky may control Chrome, and the user answers.
//
//  Nothing is sent to Chrome while it is not running: a script addressed
//  to an app launches it.
//

import AppKit
import Combine
import Foundation

struct BrowserTab: Identifiable, Hashable {
    /// Chrome hands its ids out as text.
    let windowID: String
    let tabID: String
    /// Position in its window, from 1, as Chrome counts it.
    let index: Int
    let title: String
    let url: URL?
    /// The tab shown in its window.
    let isActive: Bool
    /// Its window is Chrome's frontmost.
    let isInFrontWindow: Bool

    var id: String { "\(windowID)-\(tabID)" }

    /// The site, without "www.", for its icon.
    var host: String? {
        guard let host = url?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

final class BrowserTabsService: ObservableObject {
    static let shared = BrowserTabsService()

    static let browserBundleIdentifier = "com.google.Chrome"

    /// Chrome's tabs, front window first. Nil while Chrome is not running,
    /// has not answered, or may not be controlled: the sidebar then shows
    /// Chrome as an ordinary app.
    @Published private(set) var tabs: [BrowserTab]?

    private var timer: Timer?
    private var isReading = false

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    private var isBrowserRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.browserBundleIdentifier).isEmpty
    }

    // MARK: - Reading

    func refresh() {
        guard isBrowserRunning else {
            if tabs != nil {
                tabs = nil
            }
            return
        }
        guard !isReading else { return }
        isReading = true

        Task { [weak self] in
            let result = try? await AppleScriptService.shared.descriptor(source: Self.listScript)
            let parsed = result.flatMap(Self.parse).map(Self.removingWebAppWindows)
            await MainActor.run {
                guard let self else { return }
                self.isReading = false
                if self.tabs != parsed {
                    self.tabs = parsed
                }
            }
        }
    }

    /// One entry per window: its id, its active tab, whether it is in
    /// front, then the ids, addresses and titles of all its tabs at once.
    /// Asking for every tab's property in one go keeps Chrome to a few
    /// replies per window, and the script queue free for clicks.
    private static let listScript = """
    tell application id "\(browserBundleIdentifier)"
        set output to {}
        set windowIndex to 0
        repeat with aWindow in windows
            set windowIndex to windowIndex + 1
            set end of output to {id of aWindow, active tab index of aWindow, (windowIndex = 1), id of every tab of aWindow, URL of every tab of aWindow, title of every tab of aWindow}
        end repeat
        return output
    end tell
    """

    private static func parse(_ descriptor: NSAppleEventDescriptor) -> [BrowserTab]? {
        var result: [BrowserTab] = []
        // Apple Event lists are 1-based.
        for windowIndex in stride(from: 1, through: descriptor.numberOfItems, by: 1) {
            guard let window = descriptor.atIndex(windowIndex), window.numberOfItems == 6,
                  let windowID = window.atIndex(1)?.stringValue,
                  let ids = window.atIndex(4), let urls = window.atIndex(5), let titles = window.atIndex(6)
            else { continue }

            let activeIndex = Int(window.atIndex(2)?.int32Value ?? 0)
            let isFront = window.atIndex(3)?.booleanValue ?? false
            for tabIndex in stride(from: 1, through: ids.numberOfItems, by: 1) {
                guard let tabID = ids.atIndex(tabIndex)?.stringValue else { continue }
                result.append(BrowserTab(
                    windowID: windowID,
                    tabID: tabID,
                    index: tabIndex,
                    title: titles.atIndex(tabIndex)?.stringValue ?? "",
                    url: URL(string: urls.atIndex(tabIndex)?.stringValue ?? ""),
                    isActive: tabIndex == activeIndex,
                    isInFrontWindow: isFront
                ))
            }
        }
        return result
    }

    /// Chrome lists the windows of its installed web apps (Google Chat,
    /// say) among its own. Those apps already have their own row: a window
    /// whose only tab sits under a running web app's address is left out.
    private static func removingWebAppWindows(_ tabs: [BrowserTab]) -> [BrowserTab] {
        let startURLs = webAppStartURLs()
        guard !startURLs.isEmpty else { return tabs }

        let tabCounts = Dictionary(grouping: tabs, by: \.windowID).mapValues(\.count)
        return tabs.filter { tab in
            guard tabCounts[tab.windowID] == 1, let address = tab.url?.absoluteString else { return true }
            return !startURLs.contains { address.hasPrefix($0) }
        }
    }

    private static func webAppStartURLs() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.bundleIdentifier?.hasPrefix("\(browserBundleIdentifier).app.") == true,
                  let bundleURL = app.bundleURL,
                  let info = Bundle(url: bundleURL)?.infoDictionary,
                  let start = info["CrAppModeShortcutURL"] as? String, !start.isEmpty
            else { return nil }
            return start
        }
    }

    // MARK: - Actions

    /// Brings the tab's window forward, shows the tab, and activates Chrome.
    /// The tab is reached by its position, checked against its id; only
    /// when the tabs have moved since the last read are they searched.
    func focus(_ tab: BrowserTab) {
        // Shown as the current tab right away, without waiting for Chrome.
        tabs = tabs?.map { other in
            BrowserTab(
                windowID: other.windowID,
                tabID: other.tabID,
                index: other.index,
                title: other.title,
                url: other.url,
                isActive: other.windowID == tab.windowID ? other.id == tab.id : other.isActive,
                isInFrontWindow: other.windowID == tab.windowID
            )
        }
        run("""
        tell application id "\(Self.browserBundleIdentifier)"
            set aWindow to window id "\(tab.windowID)"
            if (count of tabs of aWindow) >= \(tab.index) and (id of tab \(tab.index) of aWindow as text) is "\(tab.tabID)" then
                set active tab index of aWindow to \(tab.index)
            else
                set tabIds to id of every tab of aWindow
                repeat with tabIndex from 1 to count of tabIds
                    if (item tabIndex of tabIds as text) is "\(tab.tabID)" then
                        set active tab index of aWindow to tabIndex
                        exit repeat
                    end if
                end repeat
            end if
            set index of aWindow to 1
            activate
        end tell
        """)
    }

    func close(_ tab: BrowserTab) {
        tabs?.removeAll { $0.id == tab.id }
        run("""
        tell application id "\(Self.browserBundleIdentifier)"
            close (tab id "\(tab.tabID)" of window id "\(tab.windowID)")
        end tell
        """)
    }

    /// Closes every tab listed in the sidebar, the web apps' windows aside.
    func closeAll() {
        guard let tabs, !tabs.isEmpty else { return }
        let targets = tabs
        self.tabs = []
        let lines = targets.map { tab in
            "close (tab id \"\(tab.tabID)\" of window id \"\(tab.windowID)\")"
        }
        run("""
        tell application id "\(Self.browserBundleIdentifier)"
            \(lines.joined(separator: "\n    "))
        end tell
        """)
    }

    /// The open tab for a pinned site: the one in front when several are on
    /// the same host.
    func tab(for site: SidebarPinnedSite) -> BrowserTab? {
        let matches = (tabs ?? []).filter { site.matches($0.url) }
        return matches.first { $0.isActive && $0.isInFrontWindow }
            ?? matches.first { $0.isActive }
            ?? matches.first
    }

    /// Goes to a pinned site: its open tab when there is one, otherwise a
    /// new tab, launching Chrome when it is not running.
    func openOrFocus(_ site: SidebarPinnedSite) {
        if let tab = tab(for: site) {
            focus(tab)
        } else {
            open(site.url)
        }
    }

    /// Opens an address in a new tab of Chrome's front window, or a new
    /// window when it has none, and brings Chrome forward.
    func open(_ url: URL) {
        guard let browserURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.browserBundleIdentifier
        ) else {
            NSWorkspace.shared.open(url)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: browserURL, configuration: configuration) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.refresh()
            }
        }
    }

    private func run(_ source: String) {
        Task { [weak self] in
            _ = try? await AppleScriptService.shared.descriptor(source: source)
            await MainActor.run {
                self?.refresh()
            }
        }
    }
}

//
//  BrowserTabsService.swift
//  Docky
//
//  The open tabs of the browser, Chrome or Dia, so the sidebar can list
//  them among the apps, each site as its own row, the way Arc mixes them.
//
//  Both answer AppleScript: the list of their windows and tabs, which tab
//  is active, and commands to switch to a tab or close it. Their
//  dictionaries differ (Chrome has an active tab index, Dia an isFocused
//  flag per tab and a `focus` command), so each has its own scripts. The
//  list is read again every 1.5 s while the browser runs; the first read
//  asks macOS whether Docky may control it, and the user answers.
//
//  One browser at a time: the one last brought forward while both run,
//  otherwise the default browser when it is a supported one, unless only
//  the other is running.
//
//  Nothing is sent to a browser while it is not running: a script
//  addressed to an app launches it.
//

import AppKit
import Combine
import Foundation

/// The browsers whose tabs the sidebar can list.
enum SupportedBrowser: String, CaseIterable {
    case chrome = "com.google.Chrome"
    case dia = "company.thebrowser.dia"

    var bundleIdentifier: String { rawValue }

    /// Where the browser keeps its profiles ("Default", "Profile 1"…),
    /// each with Chromium's Bookmarks and Favicons files.
    var profilesDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .chrome: return home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        case .dia: return home.appendingPathComponent("Library/Application Support/Dia/User Data", isDirectory: true)
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
    }

    /// The profile folders of every supported browser, for bookmarks and
    /// favicons.
    static func profileDirectories() -> [URL] {
        allCases.flatMap { browser -> [URL] in
            let root = browser.profilesDirectory
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
            return names.sorted()
                .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
                .map { root.appendingPathComponent($0, isDirectory: true) }
        }
    }
}

struct BrowserTab: Identifiable, Hashable {
    /// The browser hands its ids out as text.
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

    /// The browser whose tabs are listed, for the views that tell its
    /// app row and its tabs apart.
    static var browserBundleIdentifier: String { shared.browser.bundleIdentifier }

    /// The browser whose tabs are listed (`preferredBrowser()`).
    @Published private(set) var browser: SupportedBrowser = .chrome

    /// The browser's tabs, front window first. Nil while it is not running,
    /// has not answered, or may not be controlled: the sidebar then shows
    /// it as an ordinary app.
    @Published private(set) var tabs: [BrowserTab]?

    private var timer: Timer?
    private var isReading = false
    /// Bumped whenever the list is changed here ahead of the browser (a
    /// tab closed or brought forward). A read started before that answers
    /// with the old list and is thrown away.
    private var localChangeCount = 0
    /// Tabs closed from the sidebar, with when, kept out of the list until
    /// a read no longer has them. The browser can still list a tab for a
    /// moment after closing it; without this it would come back on screen
    /// and need a second click.
    private var closingTabs: [String: Date] = [:]
    private static let closingGracePeriod: TimeInterval = 5
    /// The supported browser last brought to the front.
    private var lastActiveBrowser: SupportedBrowser?

    private init() {
        if let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            lastActiveBrowser = SupportedBrowser(rawValue: frontmost)
        }
        browser = preferredBrowser()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let browser = app.bundleIdentifier.flatMap(SupportedBrowser.init(rawValue:))
            else { return }
            self?.lastActiveBrowser = browser
            self?.refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    /// The browser last brought forward when it still runs; otherwise the
    /// default browser when it is Chrome or Dia and either it runs or
    /// neither does; otherwise the supported one that runs.
    private func preferredBrowser() -> SupportedBrowser {
        let running = SupportedBrowser.allCases.filter(\.isRunning)
        if let lastActiveBrowser, running.contains(lastActiveBrowser) {
            return lastActiveBrowser
        }
        let defaultBrowser = URL(string: "https://example.com")
            .flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
            .flatMap(SupportedBrowser.init(rawValue:))
        if let defaultBrowser, running.isEmpty || running.contains(defaultBrowser) {
            return defaultBrowser
        }
        return running.first ?? defaultBrowser ?? .chrome
    }

    // MARK: - Reading

    func refresh() {
        let preferred = preferredBrowser()
        if preferred != browser {
            browser = preferred
            tabs = nil
        }
        guard browser.isRunning else {
            if tabs != nil {
                tabs = nil
            }
            return
        }
        guard !isReading else { return }
        isReading = true

        let browser = browser
        let changeCount = localChangeCount
        Task { [weak self] in
            let result = try? await AppleScriptService.shared.descriptor(source: Self.listScript(for: browser))
            let read = result.flatMap(Self.parse).map(Self.removingWebAppWindows)
            await MainActor.run {
                guard let self else { return }
                self.isReading = false
                guard self.browser == browser else { return }
                // Changed here while the browser was answering: its answer
                // is already out of date. Ask again.
                guard changeCount == self.localChangeCount else {
                    self.refresh()
                    return
                }
                let parsed = read.map(self.removingClosingTabs)
                if self.tabs != parsed {
                    #if DEBUG
                    Self.logForDebugging("\(browser.bundleIdentifier): " + (parsed.map { "\($0.count) tabs, \($0.filter(\.isActive).count) active" } ?? "no answer"))
                    #endif
                    self.tabs = parsed
                }
            }
        }
    }

    /// One entry per window: its id, its active tab, whether it is in
    /// front, then the ids, addresses and titles of all its tabs at once.
    /// Asking for every tab's property in one go keeps Chrome to a few
    /// replies per window, and the script queue free for clicks.
    private static func listScript(for browser: SupportedBrowser) -> String {
        browser == .dia ? diaListScript : chromeListScript
    }

    private static let chromeListScript = """
    tell application id "\(SupportedBrowser.chrome.bundleIdentifier)"
        set output to {}
        set windowIndex to 0
        repeat with aWindow in windows
            set windowIndex to windowIndex + 1
            set end of output to {id of aWindow, active tab index of aWindow, (windowIndex = 1), id of every tab of aWindow, URL of every tab of aWindow, title of every tab of aWindow}
        end repeat
        return output
    end tell
    """

    /// Dia has no active tab index: each tab says whether it is the one
    /// shown. The same six fields are built tab by tab, the active index
    /// found from that flag, and a tab that fails to answer is skipped.
    private static let diaListScript = """
    tell application id "\(SupportedBrowser.dia.bundleIdentifier)"
        set output to {}
        set windowIndex to 0
        repeat with aWindow in windows
            set windowIndex to windowIndex + 1
            try
                set tabIds to {}
                set tabURLs to {}
                set tabTitles to {}
                set activeIndex to 0
                set tabIndex to 0
                repeat with aTab in tabs of aWindow
                    try
                        set tabID to (id of aTab) as text
                        set tabURL to ""
                        try
                            set tabURL to (URL of aTab) as text
                        end try
                        set tabTitle to ""
                        try
                            set tabTitle to (title of aTab) as text
                        end try
                        set tabIndex to tabIndex + 1
                        set end of tabIds to tabID
                        set end of tabURLs to tabURL
                        set end of tabTitles to tabTitle
                        try
                            if isFocused of aTab then set activeIndex to tabIndex
                        end try
                    end try
                end repeat
                set end of output to {(id of aWindow) as text, activeIndex, (windowIndex = 1), tabIds, tabURLs, tabTitles}
            end try
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
            guard app.bundleIdentifier?.hasPrefix("\(SupportedBrowser.chrome.bundleIdentifier).app.") == true,
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
        localChangeCount += 1
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
        if browser == .dia {
            run("""
            tell application id "\(browser.bundleIdentifier)"
                \(Self.diaTabLoop(tab, command: "focus aTab"))
                activate
            end tell
            """)
            return
        }
        run("""
        tell application id "\(browser.bundleIdentifier)"
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

    /// Leaves out the tabs being closed. A tab the read no longer lists is
    /// closed for good and forgotten; one still listed after the grace
    /// period did not close, and shows again.
    private func removingClosingTabs(_ tabs: [BrowserTab]) -> [BrowserTab] {
        guard !closingTabs.isEmpty else { return tabs }
        let listed = Set(tabs.map(\.id))
        let now = Date()
        closingTabs = closingTabs.filter { id, date in
            listed.contains(id) && now.timeIntervalSince(date) < Self.closingGracePeriod
        }
        return tabs.filter { closingTabs[$0.id] == nil }
    }

    func close(_ tab: BrowserTab) {
        tabs?.removeAll { $0.id == tab.id }
        closingTabs[tab.id] = Date()
        localChangeCount += 1
        if browser == .dia {
            run("""
            tell application id "\(browser.bundleIdentifier)"
                \(Self.diaTabLoop(tab, command: "close aTab"))
            end tell
            """)
            return
        }
        run("""
        tell application id "\(browser.bundleIdentifier)"
            close (tab id "\(tab.tabID)" of window id "\(tab.windowID)")
        end tell
        """)
    }

    /// Closes every tab listed in the sidebar, the web apps' windows aside.
    func closeAll() {
        guard let tabs, !tabs.isEmpty else { return }
        let targets = tabs
        self.tabs = []
        let now = Date()
        for tab in targets {
            closingTabs[tab.id] = now
        }
        localChangeCount += 1
        let lines = targets.map { tab in
            browser == .dia
                ? Self.diaTabLoop(tab, command: "close aTab")
                : "close (tab id \"\(tab.tabID)\" of window id \"\(tab.windowID)\")"
        }
        run("""
        tell application id "\(browser.bundleIdentifier)"
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
            withBundleIdentifier: browser.bundleIdentifier
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

    /// Dia's tabs are reached by walking its windows and tabs and comparing
    /// ids, the way its own Raycast extension does.
    private static func diaTabLoop(_ tab: BrowserTab, command: String) -> String {
        """
        repeat with aWindow in windows
            if ((id of aWindow) as text) is "\(tab.windowID)" then
                repeat with aTab in tabs of aWindow
                    if ((id of aTab) as text) is "\(tab.tabID)" then
                        \(command)
                        exit repeat
                    end if
                end repeat
                exit repeat
            end if
        end repeat
        """
    }

    #if DEBUG
    /// Debug builds note each change of the tab list in the temporary
    /// folder (docky-browser-tabs.log), to check a browser answers.
    private static func logForDebugging(_ line: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("docky-browser-tabs.log")
        let entry = "\(Date()) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }
    #endif

    private func run(_ source: String) {
        Task { [weak self] in
            _ = try? await AppleScriptService.shared.descriptor(source: source)
            await MainActor.run {
                self?.refresh()
            }
        }
    }
}

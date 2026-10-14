//
//  SidebarFaviconStore.swift
//  Docky
//
//  Website icons for the sidebar. An app's dock icon is a mark baked onto
//  a plate; the icon its maker's website uses in a browser tab is very
//  often the same mark on its own, on a transparent background. When one
//  can be found, the sidebar shows it in place of a glyph cut out of the
//  dock icon.
//
//  Finding it takes two guesses:
//
//    1. The website, from the app's bundle identifier read backwards
//       (`com.spotify.client` -> spotify.com). A short table corrects the
//       apps whose identifier points somewhere else. Apps from a maker
//       of many (Apple, Google, Microsoft, Adobe) are skipped unless the
//       table names their own site: the maker's site has one icon for
//       all of them.
//    2. The icon, from the page's `<link rel="icon">` tags, preferring a
//       vector icon, then the largest bitmap, then `/favicon.ico`.
//
//  An icon is kept only if it is large enough to stay sharp and is not a
//  full opaque square, which would be a plate all over again. Kept icons
//  are stored in `~/Library/Application Support/Docky/SidebarFavicons/`;
//  an app with none is not asked about again for a week.
//
//  The same lookup gives the sites open in Chrome's tabs their icon, by
//  host (`icon(forSite:)`).
//
//  Each site receives one ordinary page request and one image request,
//  once. Nothing is sent to any third party.
//

import AppKit
import Combine
import Foundation

final class SidebarFaviconStore: ObservableObject {
    static let shared = SidebarFaviconStore()

    /// Bumped when an icon arrives, so views redraw.
    @Published private(set) var revision = 0

    private let directoryURL: URL
    private var iconsByBundleIdentifier: [String: SidebarPackIcon] = [:]
    private var missingBundleIdentifiers: Set<String> = []
    private var inFlight: Set<String> = []
    /// When each kept icon was last asked for again, this session.
    private var checkedDates: [String: Date] = [:]
    private let defaults = UserDefaults.standard

    private static let failuresKey = "docky.fork.sidebar.faviconFailures"
    private static let retryInterval: TimeInterval = 7 * 24 * 60 * 60
    /// Smallest bitmap, in pixels, that still looks sharp at the size the
    /// sidebar draws icons on a Retina display.
    private static let minimumPixelSide = 48
    private static let fileExtensions = ["svg", "png", "ico", "jpg", "gif", "webp"]

    /// Sites for apps whose bundle identifier does not lead to them.
    private static let knownSites: [String: String] = [
        "com.anthropic.claudefordesktop": "claude.ai",
        "com.google.Chrome": "www.google.com/chrome",
        "com.automattic.SimplenoteMac": "simplenote.com",
        "com.cron.electron": "calendar.notion.so",
        "company.thebrowser.dia": "diabrowser.com",
        "company.thebrowser.Browser": "arc.net",
        "com.tinyspeck.slackmacgap": "slack.com",
        "com.hnc.Discord": "discord.com",
        "notion.id": "notion.so",
        "md.obsidian": "obsidian.md",
        "com.microsoft.VSCode": "code.visualstudio.com",
        "com.todesktop.230313mzl4w4u92": "cursor.com",
        "com.figma.Desktop": "figma.com",
        "com.linear": "linear.app",
        "ru.keepcoder.Telegram": "telegram.org",
        "net.whatsapp.WhatsApp": "whatsapp.com",
        "org.mozilla.firefox": "firefox.com",
        "com.openai.chat": "chatgpt.com",
        "com.bitwarden.desktop": "bitwarden.com"
    ]

    private static let multiProductMakers: Set<String> = [
        "apple", "google", "microsoft", "adobe", "jetbrains", "amazon", "meta", "facebook",
        // Not makers at all: the prefixes app-building tools give by default.
        "electron", "todesktop", "github", "example"
    ]

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        directoryURL = support
            .appendingPathComponent("Docky", isDirectory: true)
            .appendingPathComponent("SidebarFavicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    // MARK: - Lookup

    /// The website icon for an app, if one has been found. The first call
    /// for an app starts the search and returns nil; the view is redrawn
    /// when the icon arrives.
    func icon(forBundleIdentifier bundleIdentifier: String) -> SidebarPackIcon? {
        icon(forKey: bundleIdentifier) { Self.site(forBundleIdentifier: bundleIdentifier) }
    }

    /// The icon of a website open in a browser tab, by its host. A tab's
    /// icon is drawn small, so the rules are looser than for an app: a
    /// 16 px bitmap will do, and so will one on its own square. When the
    /// host has none (a subdomain behind a sign-in page, say), its parent
    /// domain is asked.
    func icon(forSite host: String) -> SidebarPackIcon? {
        icon(forKey: "site-\(host)", isSite: true) { host }
    }

    private func icon(forKey key: String, isSite: Bool = false, site: () -> String?) -> SidebarPackIcon? {
        if let cached = iconsByBundleIdentifier[key] {
            revalidateIfStale(key: key, isSite: isSite, site: site)
            return cached
        }
        guard !missingBundleIdentifiers.contains(key) else { return nil }

        if let stored = loadStoredIcon(forBundleIdentifier: key) {
            iconsByBundleIdentifier[key] = stored
            revalidateIfStale(key: key, isSite: isSite, site: site)
            return stored
        }

        guard let site = site(), !failedRecently(key) else {
            missingBundleIdentifiers.insert(key)
            return nil
        }

        if !inFlight.contains(key) {
            inFlight.insert(key)
            Task { [weak self] in
                await self?.fetch(bundleIdentifier: key, sites: isSite ? Self.siteAndParent(site) : [site], isSite: isSite)
            }
        }
        return nil
    }

    /// A kept icon is asked for again once it is older than this, so a
    /// site that changes its icon shows the new one: an hour for a site
    /// open in a tab, a day for an app's site. The old icon stays on screen
    /// until a new one has arrived, and stays for good if none does.
    private static let siteRevalidationInterval: TimeInterval = 60 * 60
    private static let appRevalidationInterval: TimeInterval = 24 * 60 * 60

    private func revalidateIfStale(key: String, isSite: Bool, site: () -> String?) {
        guard !inFlight.contains(key) else { return }
        let interval = isSite ? Self.siteRevalidationInterval : Self.appRevalidationInterval
        let lastChecked = checkedDates[key] ?? storedFileURL(forBundleIdentifier: key).flatMap { url in
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        } ?? .distantPast
        guard Date().timeIntervalSince(lastChecked) > interval, let site = site() else { return }

        checkedDates[key] = Date()
        inFlight.insert(key)
        Task { [weak self] in
            await self?.fetch(
                bundleIdentifier: key,
                sites: isSite ? Self.siteAndParent(site) : [site],
                isSite: isSite,
                isRevalidation: true
            )
        }
    }

    // MARK: - Site

    /// The site to ask, or nil for an app that has none worth asking.
    static func site(forBundleIdentifier bundleIdentifier: String) -> String? {
        if let known = knownSites[bundleIdentifier] {
            return known
        }

        let parts = bundleIdentifier.split(separator: ".").map { String($0).lowercased() }
        guard parts.count >= 2 else { return nil }

        let topLevel = parts[0]
        let name = parts[1]
        // A maker of many apps has one site for all of them: every Apple
        // app would come back with apple.com's icon, every Office app with
        // microsoft.com's. Those are left to the table above.
        guard !multiProductMakers.contains(name) else { return nil }
        guard topLevel.count >= 2, topLevel.count <= 10, topLevel.allSatisfy(\.isLetter) else { return nil }
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return "\(name).\(topLevel)"
    }

    // MARK: - Storage

    private func storedFileURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        for fileExtension in Self.fileExtensions {
            let url = directoryURL.appendingPathComponent("\(bundleIdentifier).\(fileExtension)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func loadStoredIcon(forBundleIdentifier bundleIdentifier: String) -> SidebarPackIcon? {
        guard let url = storedFileURL(forBundleIdentifier: bundleIdentifier),
              let image = NSImage(contentsOf: url), image.isValid,
              Self.hasVisiblePixels(image)
        else { return nil }
        return Self.makeIcon(from: image)
    }

    private static func makeIcon(from image: NSImage) -> SidebarPackIcon {
        let isGlyph = SidebarIconPack.isSingleColor(image)
        if isGlyph {
            image.isTemplate = true
        }
        return SidebarPackIcon(image: image, isGlyph: isGlyph)
    }

    private func failedRecently(_ bundleIdentifier: String) -> Bool {
        let failures = defaults.dictionary(forKey: Self.failuresKey) as? [String: Double] ?? [:]
        guard let last = failures[bundleIdentifier] else { return false }
        return Date().timeIntervalSince1970 - last < Self.retryInterval
    }

    private func recordFailure(_ bundleIdentifier: String) {
        var failures = defaults.dictionary(forKey: Self.failuresKey) as? [String: Double] ?? [:]
        failures[bundleIdentifier] = Date().timeIntervalSince1970
        defaults.set(failures, forKey: Self.failuresKey)
        missingBundleIdentifiers.insert(bundleIdentifier)
    }

    // MARK: - Fetching

    /// "drive.google.com" -> ["drive.google.com", "google.com"].
    private static func siteAndParent(_ host: String) -> [String] {
        let labels = host.split(separator: ".")
        guard labels.count > 2 else { return [host] }
        return [host, labels.suffix(2).joined(separator: ".")]
    }

    private func fetch(bundleIdentifier: String, sites: [String], isSite: Bool, isRevalidation: Bool = false) async {
        defer { inFlight.remove(bundleIdentifier) }

        for site in sites {
            if await fetch(bundleIdentifier: bundleIdentifier, site: site, isSite: isSite) {
                return
            }
        }
        // A failed second look keeps the icon already found.
        if !isRevalidation {
            recordFailure(bundleIdentifier)
        }
    }

    /// True when an icon was found and kept.
    private func fetch(bundleIdentifier: String, site: String, isSite: Bool) async -> Bool {
        guard let pageURL = URL(string: "https://\(site)/") else {
            return false
        }

        var candidates: [URL] = []
        var baseURL = pageURL
        if let page = await Self.download(pageURL, limit: 600_000),
           let html = String(data: page.data, encoding: .utf8) ?? String(data: page.data, encoding: .isoLatin1) {
            baseURL = page.finalURL
            candidates = Self.iconURLs(inHTML: html, baseURL: baseURL)
        }
        if let fallback = URL(string: "/favicon.ico", relativeTo: baseURL)?.absoluteURL {
            candidates.append(fallback)
        }

        for candidate in candidates.prefix(6) {
            guard let file = await Self.download(candidate, limit: 2_000_000),
                  let image = NSImage(data: file.data), image.isValid,
                  Self.isUsable(image, isSite: isSite)
            else { continue }

            let fileExtension = Self.fileExtension(for: file.finalURL, data: file.data)
            let destination = directoryURL.appendingPathComponent("\(bundleIdentifier).\(fileExtension)")
            // A new icon in another format must not leave the old file to
            // be found first next time.
            for other in Self.fileExtensions where other != fileExtension {
                try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent("\(bundleIdentifier).\(other)"))
            }
            if let existing = try? Data(contentsOf: destination), existing == file.data {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
                return true
            }
            try? file.data.write(to: destination, options: .atomic)

            iconsByBundleIdentifier[bundleIdentifier] = Self.makeIcon(from: image)
            revision += 1
            return true
        }
        return false
    }

    private struct Download {
        let data: Data
        let finalURL: URL
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    private static func download(_ url: URL, limit: Int) async -> Download? {
        guard url.scheme == "https" else { return nil }

        var request = URLRequest(url: url)
        // Some sites answer an unknown client with an empty or blocked page.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty, data.count <= limit
        else { return nil }
        return Download(data: data, finalURL: http.url ?? url)
    }

    // MARK: - Choosing the icon

    /// Icon addresses named by the page, best first.
    static func iconURLs(inHTML html: String, baseURL: URL) -> [URL] {
        guard let tagPattern = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]) else {
            return []
        }

        let fullRange = NSRange(html.startIndex..., in: html)
        var scored: [(score: Int, url: URL)] = []

        for match in tagPattern.matches(in: html, options: [], range: fullRange) {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])

            guard let rel = attribute("rel", in: tag)?.lowercased(), rel.contains("icon"),
                  let href = attribute("href", in: tag), !href.hasPrefix("data:"),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL
            else { continue }

            let type = attribute("type", in: tag)?.lowercased() ?? ""
            let isVector = type.contains("svg") || url.pathExtension.lowercased() == "svg"
            let size = largestSize(in: attribute("sizes", in: tag) ?? "")

            var score: Int
            if rel.contains("mask-icon") {
                // A one-color vector made to be tinted: the cleanest mark
                // a site can offer.
                score = 90
            } else if isVector {
                score = 100
            } else if rel.contains("apple-touch") {
                // Usually the mark on an opaque square.
                score = 30 + min(size, 256) / 16
            } else {
                score = 40 + min(size, 256) / 8
            }
            if type.contains("x-icon") || url.pathExtension.lowercased() == "ico" {
                score -= 15
            }
            scored.append((score, url))
        }

        var seen: Set<URL> = []
        var result: [URL] = []
        for entry in scored.sorted(by: { $0.score > $1.score }) where !seen.contains(entry.url) {
            seen.insert(entry.url)
            result.append(entry.url)
        }
        return result
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: tag, options: [], range: NSRange(tag.startIndex..., in: tag))
        else { return nil }

        for group in 1...3 {
            if let range = Range(match.range(at: group), in: tag) {
                return String(tag[range])
            }
        }
        return nil
    }

    /// "32x32 180x180" -> 180.
    private static func largestSize(in sizes: String) -> Int {
        var largest = 0
        for token in sizes.lowercased().split(separator: " ") {
            if let first = token.split(separator: "x").first, let value = Int(first) {
                largest = max(largest, value)
            }
        }
        return largest
    }

    /// Sharp enough, and a mark rather than a plate. For a site's tab,
    /// any icon of 16 px or more, plate or not.
    private static func isUsable(_ image: NSImage, isSite: Bool) -> Bool {
        let hasVector = image.representations.contains { !($0 is NSBitmapImageRep) }
        if !hasVector {
            let pixelSide = image.representations.map { min($0.pixelsWide, $0.pixelsHigh) }.max() ?? 0
            guard pixelSide >= (isSite ? 16 : minimumPixelSide) else { return false }
        }
        guard hasVisiblePixels(image) else { return false }
        return isSite || !hasOpaqueCorners(image)
    }

    /// False for an icon that draws nothing here. Some SVG icons color
    /// their shapes from a stylesheet (chatgpt.com's, since October 2026),
    /// which macOS does not apply: the shapes come out with no fill.
    private static func hasVisiblePixels(_ image: NSImage) -> Bool {
        let side = 32
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return false }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return false }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        for pixel in 0..<(side * side) where bytes[pixel * 4 + 3] > 24 {
            return true
        }
        return false
    }

    /// True when all four corners are solid: a square with its own
    /// background, not a free-standing mark.
    private static func hasOpaqueCorners(_ image: NSImage) -> Bool {
        let side = 32
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return false }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return false }
        let bytes = data.assumingMemoryBound(to: UInt8.self)

        let corners = [(1, 1), (side - 2, 1), (1, side - 2), (side - 2, side - 2)]
        for (x, y) in corners where bytes[(y * side + x) * 4 + 3] < 200 {
            return false
        }
        return true
    }

    private static func fileExtension(for url: URL, data: Data) -> String {
        let fromURL = url.pathExtension.lowercased()
        if fileExtensions.contains(fromURL) {
            return fromURL
        }
        // An address without an extension: tell a vector from a bitmap by
        // how the file starts.
        let head = String(data: data.prefix(256), encoding: .utf8)?.lowercased() ?? ""
        return head.contains("<svg") || head.contains("<?xml") ? "svg" : "png"
    }
}

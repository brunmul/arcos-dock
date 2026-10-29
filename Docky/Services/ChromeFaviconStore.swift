//
//  ChromeFaviconStore.swift
//  Docky
//
//  The icon Chrome itself shows for a page, read from Chrome's own favicon
//  database. It is the only source that knows a page's icon when the page
//  sits behind a sign-in (a Claude artifact, a Gmail inbox) or sets it from
//  script: Docky's own request for the page would only see the sign-in
//  screen, and a site's icon is not a page's (every artifact on claude.ai
//  has its own).
//
//  Chrome keeps the database open, so it is copied to a temporary file and
//  the copy is read, at most every 30 s. Reading Chrome's data makes macOS
//  ask once whether Docky may access other apps' data; while it may not,
//  nothing is found here and the sidebar falls back to the site's icon
//  fetched from the web (`SidebarFaviconStore`).
//

import AppKit
import Combine
import Foundation
import SQLite3

final class ChromeFaviconStore: ObservableObject {
    static let shared = ChromeFaviconStore()

    /// Bumped when icons arrive or change, so views redraw.
    @Published private(set) var revision = 0

    private struct Entry {
        let image: NSImage?
        let checked: Date
        let data: Data?
    }

    private var entries: [String: Entry] = [:]
    private var pending: Set<String> = []
    private let queue = DispatchQueue(label: "com.brunomuller.Oriel.chrome-favicons", qos: .utility)
    /// Read on `queue` only.
    private var snapshotURLs: [URL] = []
    private var snapshotDate: Date = .distantPast

    private static let entryLifetime: TimeInterval = 30
    private static let snapshotLifetime: TimeInterval = 30

    private init() {}

    /// Chrome's icon for the page at `url`. Nil until read, and when Chrome
    /// has none for this very page; the view is redrawn when it arrives.
    func icon(for url: URL?) -> NSImage? {
        guard let url, let scheme = url.scheme, scheme.hasPrefix("http") else { return nil }
        let key = url.absoluteString
        let entry = entries[key]

        if entry.map({ Date().timeIntervalSince($0.checked) > Self.entryLifetime }) ?? true,
           !pending.contains(key) {
            pending.insert(key)
            queue.async { [weak self] in
                self?.lookUp(url, key: key)
            }
        }
        return entry?.image
    }

    // MARK: - Reading

    private func lookUp(_ url: URL, key: String) {
        refreshSnapshotIfNeeded()
        let data = snapshotURLs.lazy.compactMap { Self.iconData(for: url, in: $0) }.first

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pending.remove(key)
            let previous = self.entries[key]
            if previous?.data == data, previous != nil {
                self.entries[key] = Entry(image: previous?.image, checked: Date(), data: data)
                return
            }
            let image = data.flatMap { NSImage(data: $0) }
            self.entries[key] = Entry(image: image, checked: Date(), data: data)
            self.revision += 1
        }
    }

    /// Copies each Chrome profile's favicon database, when the copies are
    /// older than `snapshotLifetime`.
    private func refreshSnapshotIfNeeded() {
        guard Date().timeIntervalSince(snapshotDate) > Self.snapshotLifetime else { return }
        snapshotDate = Date()

        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory
            .appendingPathComponent("DockyChromeFavicons", isDirectory: true)
        try? fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)

        // Chrome's profiles, then Dia's: both keep Chromium's Favicons file.
        var copies: [URL] = []
        for (number, profile) in SupportedBrowser.profileDirectories().enumerated() {
            let source = profile.appendingPathComponent("Favicons")
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let copy = temporary.appendingPathComponent("\(number)-\(profile.lastPathComponent.replacingOccurrences(of: " ", with: "-"))")
            try? fileManager.removeItem(at: copy)
            do {
                try fileManager.copyItem(at: source, to: copy)
                copies.append(copy)
            } catch {
                continue
            }
        }
        // The default profile first: that is where most tabs live.
        snapshotURLs = copies
    }

    /// The largest bitmap Chrome keeps for the page itself.
    private static func iconData(for url: URL, in database: URL) -> Data? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(handle) }

        // The browser maps a page to the icon of wherever it ended up: a
        // page that redirected or was navigated away from in its tab keeps
        // the next site's icon (a link page showing YouTube's). An icon is
        // only taken when every page mapped to it is on the page's own
        // site, or when the icon file itself is served from that site: a
        // borrowed one falls through to the site's own icon.
        guard let host = url.host?.lowercased() else { return nil }
        let site = Self.siteDomain(of: host)
        let ownSiteOnly = """
        AND (
            f.url LIKE ?2 OR f.url LIKE ?3
            OR NOT EXISTS (
                SELECT 1 FROM icon_mapping o WHERE o.icon_id = m.icon_id
                AND o.page_url NOT LIKE ?2 AND o.page_url NOT LIKE ?3
            )
        )
        """
        let siteBindings = ["%://\(site)/%", "%.\(site)/%"]

        let exact = """
        SELECT b.image_data FROM icon_mapping m
        JOIN favicon_bitmaps b ON b.icon_id = m.icon_id
        JOIN favicons f ON f.id = m.icon_id
        WHERE m.page_url = ?1 AND length(b.image_data) > 0
        \(ownSiteOnly)
        ORDER BY b.width DESC LIMIT 1
        """
        // No icon for this very page means nothing from Chrome. Another
        // page of the same host can wear another product's icon (Flights'
        // airplane or Maps' pin on google.com), so the sidebar falls back
        // to the site's own icon instead.
        return firstBlob(handle, exact, bindings: [url.absoluteString] + siteBindings)
    }

    /// The host's last two labels ("mail.google.com" → "google.com"), close
    /// enough to tell one site from another here.
    private static func siteDomain(of host: String) -> String {
        let labels = host.split(separator: ".")
        return labels.count > 2 ? labels.suffix(2).joined(separator: ".") : host
    }

    private static func firstBlob(_ handle: OpaquePointer?, _ sql: String, bindings: [String]) -> Data? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(offset + 1), value, -1, transient)
        }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0)
        else { return nil }
        let count = Int(sqlite3_column_bytes(statement, 0))
        return Data(bytes: bytes, count: count)
    }
}

//
//  SidebarIconPack.swift
//  Docky
//
//  A custom icon pack for the sidebar: a folder of image files, each named
//  after the app or the pinned folder it stands for. An icon found there
//  replaces the app's own icon (or the folder's symbol) in the sidebar.
//
//  The folder is `~/Library/Application Support/Docky/SidebarIcons/`.
//  A file matches by its name, without the extension, compared without
//  regard to case or accents:
//
//    com.google.Chrome.svg     the app's bundle identifier, or
//    Google Chrome.png         the app's name as Finder shows it
//    Utility.pdf               a pinned folder's name
//
//  PNG, PDF, SVG, JPEG, HEIC and ICNS files are read. An icon drawn in a
//  single color is treated as a glyph and tinted with the sidebar's ink,
//  so one file serves both light and dark mode; an icon with several
//  colors is shown as it is.
//
//  The folder is watched: adding, replacing or removing a file updates the
//  sidebar at once.
//

import AppKit
import Combine
import Foundation

struct SidebarPackIcon {
    let image: NSImage
    /// True for a single-color icon, drawn in the sidebar's ink.
    let isGlyph: Bool
}

final class SidebarIconPack: ObservableObject {
    static let shared = SidebarIconPack()

    /// Bumped whenever the folder's contents change, so views redraw.
    @Published private(set) var revision = 0

    let directoryURL: URL

    private static let fileExtensions: Set<String> = ["png", "pdf", "svg", "jpg", "jpeg", "heic", "icns", "tiff"]

    /// Normalized file name (no extension) to file.
    private var filesByName: [String: URL] = [:]
    private var iconsByURL: [URL: SidebarPackIcon] = [:]
    private var appNamesByBundleIdentifier: [String: String] = [:]
    private var watcher: DispatchSourceFileSystemObject?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        directoryURL = support
            .appendingPathComponent("Docky", isDirectory: true)
            .appendingPathComponent("SidebarIcons", isDirectory: true)

        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        reload()
        startWatching()
    }

    // MARK: - Lookup

    /// The pack's icon for an app: by bundle identifier first, then by the
    /// app's name.
    func icon(forBundleIdentifier bundleIdentifier: String) -> SidebarPackIcon? {
        guard !filesByName.isEmpty else { return nil }

        if let url = filesByName[Self.normalized(bundleIdentifier)] {
            return icon(at: url)
        }
        if let name = appName(forBundleIdentifier: bundleIdentifier),
           let url = filesByName[Self.normalized(name)] {
            return icon(at: url)
        }
        return nil
    }

    /// The pack's icon for a pinned folder, by the folder's name.
    func icon(forFolderNamed name: String) -> SidebarPackIcon? {
        guard !filesByName.isEmpty, let url = filesByName[Self.normalized(name)] else { return nil }
        return icon(at: url)
    }

    func revealInFinder() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directoryURL)
    }

    // MARK: - Loading

    private func reload() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var files: [String: URL] = [:]
        for url in contents where Self.fileExtensions.contains(url.pathExtension.lowercased()) {
            files[Self.normalized(url.deletingPathExtension().lastPathComponent)] = url
        }

        filesByName = files
        // A replaced file keeps its name; drop every decoded image.
        iconsByURL.removeAll()
        revision += 1
    }

    private func icon(at url: URL) -> SidebarPackIcon? {
        if let cached = iconsByURL[url] {
            return cached
        }
        guard let image = NSImage(contentsOf: url), image.isValid else { return nil }

        let isGlyph = Self.isSingleColor(image)
        if isGlyph {
            image.isTemplate = true
        }
        let icon = SidebarPackIcon(image: image, isGlyph: isGlyph)
        iconsByURL[url] = icon
        return icon
    }

    /// The app's name as Finder shows it ("Google Chrome"), for matching a
    /// file named after the app.
    private func appName(forBundleIdentifier bundleIdentifier: String) -> String? {
        if let cached = appNamesByBundleIdentifier[bundleIdentifier] {
            return cached.isEmpty ? nil : cached
        }

        var name = ""
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            name = url.deletingPathExtension().lastPathComponent
        }
        appNamesByBundleIdentifier[bundleIdentifier] = name
        return name.isEmpty ? nil : name
    }

    private static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Whether every visible pixel of the image is the same color, give or
    /// take antialiasing: the mark of a glyph meant to be tinted.
    static func isSingleColor(_ image: NSImage) -> Bool {
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

        var reference: (Float, Float, Float)?
        var visible = 0
        var matching = 0

        for index in 0..<(side * side) {
            let alpha = Float(bytes[index * 4 + 3])
            // Faint edge pixels carry rounding noise once un-premultiplied.
            guard alpha > 96 else { continue }

            let red: Float = Float(bytes[index * 4]) / alpha
            let green: Float = Float(bytes[index * 4 + 1]) / alpha
            let blue: Float = Float(bytes[index * 4 + 2]) / alpha
            visible += 1

            guard let first = reference else {
                reference = (red, green, blue)
                matching += 1
                continue
            }
            let spread: Float = max(abs(red - first.0), max(abs(green - first.1), abs(blue - first.2)))
            if spread < 0.1 {
                matching += 1
            }
        }

        guard visible > 0 else { return false }
        return Float(matching) / Float(visible) > 0.97
    }

    // MARK: - Watching

    private func startWatching() {
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        watcher = source
    }
}

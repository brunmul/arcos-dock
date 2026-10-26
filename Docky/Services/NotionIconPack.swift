//
//  NotionIconPack.swift
//  Docky
//
//  The icons of Notion's page icon picker (filled glyphs on a 20 pt grid,
//  in the current color), and the handful from Notion's own interface,
//  from Bruno's icon library (~/Documents/Ressources/icones/notion and
//  notion-interface), bundled as IconPacks/notion-icons.json. A pinned
//  app or site can wear one of them, drawn in the theme's colors, in
//  place of its own icon.
//

import AppKit

enum NotionIconPack {
    private struct Entry: Decodable {
        let n: String
        let s: String
        let group: String
    }

    private struct File: Decodable {
        let icons: [Entry]
    }

    private static let entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "notion-icons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [] }
        return file.icons
    }()

    private static let svgs: [String: String] = Dictionary(
        entries.map { ($0.n, $0.s) },
        uniquingKeysWith: { first, _ in first }
    )

    /// The page icons' names, in alphabetical order.
    static let pageNames: [String] = entries.filter { $0.group == "Pages" }.map(\.n).sorted()

    /// The interface icons' names, in alphabetical order.
    static let interfaceNames: [String] = entries.filter { $0.group != "Pages" }.map(\.n).sorted()

    /// The page icons by first letter ("A", "B"… and "0–9"), for menus
    /// short enough to scan.
    static let pageNamesByInitial: [(initial: String, names: [String])] = {
        let grouped = Dictionary(grouping: pageNames) { name -> String in
            guard let first = name.first else { return "#" }
            return first.isLetter ? first.uppercased() : "0–9"
        }
        return grouped.keys.sorted { lhs, rhs in
            // Digits after the letters, as a footnote.
            if lhs == "0–9" { return false }
            if rhs == "0–9" { return true }
            return lhs < rhs
        }.map { ($0, grouped[$0] ?? []) }
    }()

    private static var cache: [String: NSImage] = [:]

    /// The icon as a template image, to be tinted where it is drawn; nil
    /// for a name the pack doesn't have (a Claude icon chosen before the
    /// switch), so the item falls back to its own icon.
    static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let svg = svgs[name],
              let image = NSImage(data: Data(svg.utf8)), image.isValid
        else { return nil }
        image.isTemplate = true
        cache[name] = image
        return image
    }

    /// "alarm-clock" -> "Alarm Clock", for the menus.
    static func title(of name: String) -> String {
        name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

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

    /// The color a Notion icon wears, drawn from the sidebar's theme so the
    /// icons are colored yet belong to the bar (Bruno, 26 October). Each
    /// icon keeps the same color for its name, by the same rule as Docky
    /// for Windows (`Palette.IconColor`):
    /// - Claude theme, or a theme with almost no color (Gray, Hoth...): the
    ///   folders' muted inks, without the gray;
    /// - any other theme: six hues 60° apart, starting from the hue of the
    ///   theme's more colorful end, saturation 55 %, lightness 40 % on a
    ///   light bar and 72 % on a dark one.
    /// `tint`, when set, is the color chosen by hand: that folder ink.
    static func color(forIcon name: String, tint: SidebarIconTint? = nil, theme: SidebarTheme, isDark: Bool) -> NSColor {
        if let tint {
            return tint.ink(isDark: isDark)
        }
        var hash: UInt32 = 2166136261
        for byte in name.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16777619
        }
        let (topHue, topSaturation) = hueAndSaturation(of: theme.top)
        let (bottomHue, bottomSaturation) = hueAndSaturation(of: theme.bottom)
        if theme.isClaude || max(topSaturation, bottomSaturation) < 0.15 {
            let tints = SidebarFolderGlyph.Tint.allCases.filter { $0 != .gray }
            return tints[Int(hash % UInt32(tints.count))].ink(isDark: isDark)
        }
        let hue = (topSaturation >= bottomSaturation ? topHue : bottomHue) + 60 * Double(hash % 6)
        return color(hue: hue.truncatingRemainder(dividingBy: 360), saturation: 0.55, lightness: isDark ? 0.72 : 0.40)
    }

    /// Whether the sidebar is dark: the system's mode with the Claude
    /// theme, the theme's own otherwise. For the menus, drawn outside the
    /// sidebar's SwiftUI environment.
    static func sidebarIsDark(_ theme: SidebarTheme) -> Bool {
        theme.isClaude
            ? NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            : theme.isDark
    }

    /// The icon filled with its color, for the menus.
    static func coloredImage(named name: String, tint: SidebarIconTint? = nil, theme: SidebarTheme) -> NSImage? {
        guard let template = image(named: name) else { return nil }
        let ink = color(forIcon: name, tint: tint, theme: theme, isDark: sidebarIsDark(theme))
        return NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            ink.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// a + (b − a)·t, channel by channel in sRGB, rounded to bytes as on
    /// Windows (`Palette.Mix`).
    static func mix(_ a: NSColor, _ b: NSColor, _ t: Double) -> NSColor {
        let a = bytes(of: a), b = bytes(of: b)
        func m(_ x: Double, _ y: Double) -> CGFloat { CGFloat((x + (y - x) * t).rounded()) / 255 }
        return NSColor(srgbRed: m(a.0, b.0), green: m(a.1, b.1), blue: m(a.2, b.2), alpha: 1)
    }

    /// How strongly the relief shows on a color: 1 − 0.55 × its luminance
    /// (Rec. 709 weights on sRGB bytes), so light colors get a softer
    /// gradient (Bruno, 27 October; as Windows' docky-windows 7fa65fa).
    static func reliefStrength(_ color: NSColor) -> Double {
        let c = bytes(of: color)
        let luminance = (0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2) / 255
        return 1 - 0.55 * luminance
    }

    /// Each channel times `factor`, capped at white: the hover's lift.
    static func brightened(_ color: NSColor, by factor: Double) -> NSColor {
        let c = bytes(of: color)
        func s(_ v: Double) -> CGFloat { CGFloat(min(255, (v * factor).rounded())) / 255 }
        return NSColor(srgbRed: s(c.0), green: s(c.1), blue: s(c.2), alpha: 1)
    }

    /// The bar's own color under a tile: the Claude paper or charcoal, or a
    /// theme's gradient taken 40 % of the way down (`Palette.BarColor`).
    static func barColor(theme: SidebarTheme, isDark: Bool) -> NSColor {
        if theme.isClaude {
            return isDark ? hexColor(0x1F1E1D) : hexColor(0xF5F4ED)
        }
        return mix(hexColor(theme.top), hexColor(theme.bottom), 0.4)
    }

    private static func hexColor(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func bytes(of color: NSColor) -> (Double, Double, Double) {
        let c = color.usingColorSpace(.sRGB) ?? color
        return ((c.redComponent * 255).rounded(), (c.greenComponent * 255).rounded(), (c.blueComponent * 255).rounded())
    }

    /// Hue in degrees and HSL saturation of a 0xRRGGBB color.
    private static func hueAndSaturation(of hex: Int) -> (Double, Double) {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        guard delta > 1e-6 else { return (0, 0) }
        let lightness = (high + low) / 2
        let saturation = delta / (1 - abs(2 * lightness - 1))
        let hue: Double
        if high == r {
            hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if high == g {
            hue = 60 * ((b - r) / delta + 2)
        } else {
            hue = 60 * ((r - g) / delta + 4)
        }
        return ((hue + 360).truncatingRemainder(dividingBy: 360), saturation)
    }

    private static func color(hue: Double, saturation: Double, lightness: Double) -> NSColor {
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - c / 2
        let (r, g, b): (Double, Double, Double) = switch hue {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        // Rounded to bytes, as on Windows, so both draw the same color.
        func byte(_ v: Double) -> CGFloat { CGFloat((v + m) * 255).rounded() / 255 }
        return NSColor(srgbRed: byte(r), green: byte(g), blue: byte(b), alpha: 1)
    }

    /// "alarm-clock" -> "Alarm Clock", for the menus.
    static func title(of name: String) -> String {
        name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

//
//  SidebarSuperPinColor.swift
//  Docky
//
//  The color of a super pin's line and glow (Bruno, 29 October; as
//  Windows' docky-windows d05900f): the item's own color rather than the
//  theme's accent, from the first of these that applies:
//
//    1. the color of the Notion icon it wears (the tint chosen for it, or
//       the one the theme gives it);
//    2. the main color of its icon, the app's or the site's, brought to a
//       lightness that reads on the bar;
//    3. the theme's accent (`NotionIconPack.superPinAccent`), for a gray
//       icon or a site icon not loaded yet.
//
//  Chrome pinned per profile, which takes its account's color on Windows,
//  does not exist on the Mac.
//

import AppKit
import SwiftUI

enum SidebarSuperPinColor {
    static func color(forItem id: String, theme: SidebarTheme, isDark: Bool) -> NSColor {
        let sidebar = SidebarPreferences.shared
        if let icon = sidebar.wornIcon(forItem: id) {
            return NotionIconPack.color(forIcon: icon.name, tint: icon.tint, theme: theme, isDark: isDark)
        }
        if let image = iconImage(forItem: id), let dominant = dominantColor(of: image) {
            return clamped(dominant, isDark: isDark)
        }
        return NotionIconPack.superPinAccent(theme: theme, isDark: isDark)
    }

    /// The colored image the item shows: a site's favicon; for an app, a
    /// colored icon from the pack or of its website, otherwise its own
    /// (or the one picked with "Change Icon..."). One-color glyphs are
    /// left aside: they are drawn in the bar's ink.
    private static func iconImage(forItem id: String) -> NSImage? {
        if id.hasPrefix("app-") {
            let bundleIdentifier = String(id.dropFirst(4))
            if let packIcon = SidebarIconPack.shared.icon(forBundleIdentifier: bundleIdentifier), !packIcon.isGlyph {
                return packIcon.image
            }
            if SidebarPreferences.shared.usesWebsiteIcons,
               let favicon = SidebarFaviconStore.shared.icon(forBundleIdentifier: bundleIdentifier), !favicon.isGlyph {
                return favicon.image
            }
            if let overrideURL = DockyPreferences.shared.effectiveAppIconOverrideURL(forBundleIdentifier: bundleIdentifier),
               let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
                return overrideImage
            }
            return IconCacheService.shared.icon(forBundleIdentifier: bundleIdentifier)
        }
        guard let site = SidebarPreferences.shared.pinnedSites.first(where: { SidebarPinnedItem.site($0).id == id })
        else { return nil }
        let url = BrowserTabsService.shared.tab(for: site)?.url ?? site.url
        if let image = ChromeFaviconStore.shared.icon(for: url) {
            return image
        }
        if let host = SidebarPinnedSite.host(of: url), let favicon = SidebarFaviconStore.shared.icon(forSite: host), !favicon.isGlyph {
            return favicon.image
        }
        return nil
    }

    // MARK: Main color

    private final class Entry {
        let color: NSColor?
        init(_ color: NSColor?) { self.color = color }
    }

    /// By image: the main color is worked out once per icon.
    private static let cache = NSCache<NSImage, Entry>()

    private static let side = 48

    /// The icon brought down to 48 px; pixels nearly transparent (alpha
    /// under 160), grayish (HSL saturation under 0.25), nearly black or
    /// white (lightness under 0.12 or over 0.92) left out; the others in
    /// twelve 30° slices of hue, each weighing saturation × (1 − |2·L − 1|).
    /// The heaviest slice, if it weighs over 0.5, gives the weighted mean
    /// of its pixels. Nil for an icon without a clear color.
    static func dominantColor(of image: NSImage) -> NSColor? {
        if let entry = cache.object(forKey: image) {
            return entry.color
        }
        let color = computeDominantColor(of: image)
        cache.setObject(Entry(color), forKey: image)
        return color
    }

    private static func computeDominantColor(of image: NSImage) -> NSColor? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap), let data = bitmap.bitmapData
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var weights = [Double](repeating: 0, count: 12)
        var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: 12)
        for index in 0..<(side * side) {
            let alpha = Double(data[index * 4 + 3])
            guard alpha >= 160 else { continue }
            // Premultiplied: back to the color itself.
            let r = Double(data[index * 4]) / alpha
            let g = Double(data[index * 4 + 1]) / alpha
            let b = Double(data[index * 4 + 2]) / alpha
            let (hue, saturation, lightness) = hsl(r, g, b)
            guard saturation >= 0.25, lightness >= 0.12, lightness <= 0.92 else { continue }
            let slice = min(11, Int(hue / 30))
            let weight = saturation * (1 - abs(2 * lightness - 1))
            weights[slice] += weight
            sums[slice].0 += r * weight
            sums[slice].1 += g * weight
            sums[slice].2 += b * weight
        }
        guard let heaviest = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[heaviest] > 0.5
        else { return nil }
        let weight = weights[heaviest]
        return NSColor(
            srgbRed: CGFloat(sums[heaviest].0 / weight),
            green: CGFloat(sums[heaviest].1 / weight),
            blue: CGFloat(sums[heaviest].2 / weight),
            alpha: 1
        )
    }

    /// The same hue and saturation, the HSL lightness kept within 0.30–0.55
    /// on a light bar and 0.55–0.78 on a dark one.
    static func clamped(_ color: NSColor, isDark: Bool) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return color }
        let (hue, saturation, lightness) = hsl(Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
        let range = isDark ? 0.55...0.78 : 0.30...0.55
        let target = min(max(lightness, range.lowerBound), range.upperBound)
        return fromHSL(hue: hue, saturation: saturation, lightness: target)
    }

    /// Hue in degrees, saturation and lightness of a color in 0...1.
    private static func hsl(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let high = max(r, g, b), low = min(r, g, b)
        let lightness = (high + low) / 2
        let delta = high - low
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        if high == r {
            hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if high == g {
            hue = 60 * ((b - r) / delta + 2)
        } else {
            hue = 60 * ((r - g) / delta + 4)
        }
        if hue < 0 { hue += 360 }
        return (hue, min(1, saturation), lightness)
    }

    private static func fromHSL(hue: Double, saturation: Double, lightness: Double) -> NSColor {
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - c / 2
        let (r, g, b): (Double, Double, Double)
        switch hue {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return NSColor(srgbRed: CGFloat(r + m), green: CGFloat(g + m), blue: CGFloat(b + m), alpha: 1)
    }
}

/// A super pin's glow and line, in its own color. Watches the icon
/// stores, so the color follows a favicon that arrives late.
struct SidebarSuperPinDecoration: View {
    let itemID: String
    let lineWidth: CGFloat
    let cornerRadius: CGFloat
    let isDark: Bool

    @ObservedObject private var sidebar = SidebarPreferences.shared
    @ObservedObject private var favicons = SidebarFaviconStore.shared
    @ObservedObject private var chromeFavicons = ChromeFaviconStore.shared
    @ObservedObject private var browserTabs = BrowserTabsService.shared

    var body: some View {
        let color = SidebarSuperPinColor.color(forItem: itemID, theme: sidebar.theme, isDark: isDark)
        ZStack {
            SidebarSuperPinGlow(accent: color, isDark: isDark)
                .clipShape(RoundedRectangle(cornerRadius: max(0, cornerRadius - 1), style: .continuous))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: color).opacity(0.85), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}

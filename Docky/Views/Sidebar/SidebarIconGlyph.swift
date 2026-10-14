//
//  SidebarIconGlyph.swift
//  Docky
//
//  Turns an app's icon into a single-color glyph with no plate behind it:
//  the white spark without its orange square, the envelope without its
//  blue one. The mark is drawn in the icon's main color (that orange,
//  that blue), so a column of apps reads as a set of marks instead of a
//  set of colored squares, and each stays recognizable.
//
//  macOS has no such version of an icon to hand out, so this is image
//  processing, and a guess:
//
//    1. Find the plate, the rounded square nearly every icon sits on, as
//       the opaque part of the picture.
//    2. Read the plate's color just inside its left and right edges, at
//       the top and at the bottom, which also follows the vertical
//       gradient most plates have.
//    3. Whatever differs from that color is the mark. Its opacity grows
//       with the difference, which keeps soft edges soft.
//    4. Crop to the mark and scale it back up, so marks from different
//       icons end up at a similar size.
//    5. Pick the one color that stands for the icon, to draw the mark in.
//
//  It works when an icon is a shape on a plain plate. An icon that is a
//  full picture (Finder's face) has no plate color to remove; for those
//  the mark is built from how far each pixel's brightness is from the
//  icon's usual brightness, which keeps the picture's main shapes.
//

import AppKit
import CoreGraphics

/// An icon reduced to its mark: a template image and the color that stands
/// for the icon. `tint` is nil when the icon has no color of its own.
final class SidebarGlyph {
    let image: NSImage
    let tint: NSColor?
    /// False for a placeholder kept in the cache so a failed extraction is
    /// not attempted again on every redraw.
    let isUsable: Bool

    init(image: NSImage, tint: NSColor?, isUsable: Bool) {
        self.image = image
        self.tint = tint
        self.isUsable = isUsable
    }
}

enum SidebarIconGlyph {
    private static let cache: NSCache<NSString, SidebarGlyph> = {
        let cache = NSCache<NSString, SidebarGlyph>()
        cache.countLimit = 128
        return cache
    }()

    static func forget(key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    /// Working size, in pixels. Large enough for a 20pt tile at 2x.
    private static let side = 96

    /// The glyph for `image`: a template image, and the color to draw it
    /// in. `key` identifies the icon for caching. Nil when nothing could
    /// be extracted, in which case the icon is best shown as it is.
    static func glyph(for image: NSImage, key: String) -> SidebarGlyph? {
        let cacheKey = key as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached.isUsable ? cached : nil
        }

        let result = makeGlyph(from: image) ?? SidebarGlyph(image: image, tint: nil, isUsable: false)
        cache.setObject(result, forKey: cacheKey)
        #if DEBUG
        dumpForInspection(source: image, glyph: result.image, key: key)
        #endif
        return result.isUsable ? result : nil
    }

    // MARK: - Pipeline

    private static func makeGlyph(from image: NSImage) -> SidebarGlyph? {
        guard let source = Bitmap(image: image, side: side) else { return nil }

        let extraction = extractMask(from: source)
        guard let cropped = cropToContent(extraction.mask, side: side) else { return nil }
        guard let cgImage = makeImage(fromMask: cropped, side: side) else { return nil }

        let glyph = NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
        glyph.isTemplate = true
        let tint = principalColor(of: source, mask: extraction.mask, plate: extraction.plate)
        return SidebarGlyph(image: glyph, tint: tint, isUsable: true)
    }

    /// Opacity of the mark at each pixel, 0...1, row by row from the top,
    /// and the plate's color when a plain plate was found and removed.
    private static func extractMask(from source: Bitmap) -> (mask: [Float], plate: (Float, Float, Float)?) {
        let side = source.side
        var mask = [Float](repeating: 0, count: side * side)

        // The plate: per row, the span of fully opaque pixels.
        var rowMin = [Int](repeating: -1, count: side)
        var rowMax = [Int](repeating: -1, count: side)
        var colMin = [Int](repeating: -1, count: side)
        var colMax = [Int](repeating: -1, count: side)
        var opaqueCount = 0

        for y in 0..<side {
            for x in 0..<side where source.alpha(x, y) > 0.9 {
                opaqueCount += 1
                if rowMin[y] < 0 { rowMin[y] = x }
                rowMax[y] = x
                if colMin[x] < 0 { colMin[x] = y }
                colMax[x] = y
            }
        }

        let plateRows = (0..<side).filter { rowMin[$0] >= 0 && rowMax[$0] - rowMin[$0] > side / 2 }

        // No plate to speak of: the picture is already a free-standing
        // shape (a custom icon with a transparent background, say). Its
        // own outline is the mark.
        guard plateRows.count > side / 3, let top = plateRows.first, let bottom = plateRows.last, bottom > top else {
            for index in 0..<(side * side) {
                mask[index] = source.alpha(index % side, index / side)
            }
            return (mask, nil)
        }

        // Plate color at the top and at the bottom, from samples taken a
        // little inside its left and right edges. Medians, so a mark that
        // reaches the edge on a few rows does not skew them.
        func samples(in rows: [Int]) -> [(Float, Float, Float)] {
            var result: [(Float, Float, Float)] = []
            for y in rows {
                let inset = max(3, (rowMax[y] - rowMin[y]) / 12)
                result.append(source.color(rowMin[y] + inset, y))
                result.append(source.color(rowMax[y] - inset, y))
            }
            return result
        }

        let bandHeight = max(4, plateRows.count / 3)
        let topColor = median(of: samples(in: Array(plateRows.prefix(bandHeight))))
        let bottomColor = median(of: samples(in: Array(plateRows.suffix(bandHeight))))

        // Icons carry a bright rim along the plate's edge and a shadow
        // around it. Neither is part of the mark.
        let rim = max(3, side / 20)
        let span = Float(bottom - top)
        var total: Float = 0

        for y in top...bottom where rowMin[y] >= 0 {
            let progress: Float = Float(y - top) / span
            let plateRed: Float = topColor.0 + (bottomColor.0 - topColor.0) * progress
            let plateGreen: Float = topColor.1 + (bottomColor.1 - topColor.1) * progress
            let plateBlue: Float = topColor.2 + (bottomColor.2 - topColor.2) * progress
            let plate: (Float, Float, Float) = (plateRed, plateGreen, plateBlue)

            let firstX = rowMin[y] + rim
            let lastX = rowMax[y] - rim
            guard firstX <= lastX else { continue }

            for x in firstX...lastX {
                guard colMin[x] >= 0, y >= colMin[x] + rim, y <= colMax[x] - rim else { continue }

                let color = source.color(x, y)
                let dr: Float = color.0 - plate.0
                let dg: Float = color.1 - plate.1
                let db: Float = color.2 - plate.2
                let squared: Float = dr * dr + dg * dg + db * db
                let distance: Float = (squared / 3).squareRoot()
                let value: Float = smoothstep(0.07, 0.24, distance) * source.alpha(x, y)
                mask[y * side + x] = value
                total += value
            }
        }

        // How much of the plate came out as "mark". Next to nothing, or
        // nearly all of it, means the plate color was a bad guess: the
        // icon is a full picture.
        let coverage = total / Float(max(opaqueCount, 1))
        if coverage < 0.02 || coverage > 0.72 {
            let fallback = brightnessMask(
                from: source,
                rowMin: rowMin,
                rowMax: rowMax,
                colMin: colMin,
                colMax: colMax,
                rim: rim
            )
            return (fallback, nil)
        }

        let plate: (Float, Float, Float) = (
            (topColor.0 + bottomColor.0) / 2,
            (topColor.1 + bottomColor.1) / 2,
            (topColor.2 + bottomColor.2) / 2
        )
        return (mask, plate)
    }

    // MARK: - Color

    /// The one color that stands for the icon: its plate when the plate is
    /// colored (the orange behind a white spark), otherwise the strongest
    /// hue of the mark itself (the blue of a letter on a white plate). Nil
    /// for an icon with no real color, which keeps the sidebar's ink.
    private static func principalColor(
        of source: Bitmap,
        mask: [Float],
        plate: (Float, Float, Float)?
    ) -> NSColor? {
        if let plate {
            let hsv = hueSaturationValue(plate)
            if hsv.saturation > 0.28, hsv.value > 0.22 {
                return readableColor(plate)
            }
        }

        // Hue histogram of the mark, weighted by how vivid each pixel is,
        // so the answer is one of the icon's actual colors and not the
        // mud that averaging several would give.
        let side = source.side
        let binCount = 12
        var weights = [Float](repeating: 0, count: binCount)
        var reds = [Float](repeating: 0, count: binCount)
        var greens = [Float](repeating: 0, count: binCount)
        var blues = [Float](repeating: 0, count: binCount)
        var maskTotal: Float = 0

        for index in 0..<(side * side) where mask[index] > 0.5 {
            maskTotal += mask[index]
            let color = source.color(index % side, index / side)
            let hsv = hueSaturationValue(color)
            guard hsv.saturation > 0.25, hsv.value > 0.2 else { continue }

            let weight: Float = hsv.saturation * hsv.value * mask[index]
            let bin = min(binCount - 1, Int(hsv.hue * Float(binCount)))
            weights[bin] += weight
            reds[bin] += color.0 * weight
            greens[bin] += color.1 * weight
            blues[bin] += color.2 * weight
        }

        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }),
              weights[best] > maskTotal * 0.05, weights[best] > 0
        else { return nil }

        let color: (Float, Float, Float) = (
            reds[best] / weights[best],
            greens[best] / weights[best],
            blues[best] / weights[best]
        )
        return readableColor(color)
    }

    private static func hueSaturationValue(
        _ color: (Float, Float, Float)
    ) -> (hue: Float, saturation: Float, value: Float) {
        let maximum: Float = max(color.0, max(color.1, color.2))
        let minimum: Float = min(color.0, min(color.1, color.2))
        let delta: Float = maximum - minimum
        guard maximum > 0, delta > 0 else { return (0, 0, maximum) }

        var hue: Float
        if maximum == color.0 {
            hue = (color.1 - color.2) / delta
        } else if maximum == color.1 {
            hue = 2 + (color.2 - color.0) / delta
        } else {
            hue = 4 + (color.0 - color.1) / delta
        }
        hue /= 6
        if hue < 0 {
            hue += 1
        }
        return (hue, delta / maximum, maximum)
    }

    /// The color adjusted to read as a thin mark on the sidebar: held back
    /// from very light on the paper surface, lifted from very dark on the
    /// charcoal one, and a touch less saturated either way.
    private static func readableColor(_ color: (Float, Float, Float)) -> NSColor {
        let base = NSColor(
            srgbRed: CGFloat(color.0),
            green: CGFloat(color.1),
            blue: CGFloat(color.2),
            alpha: 1
        )
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Yellows and greens look far lighter than blues at the same
        // brightness; darken by how light the color actually appears.
        let weightedRed: Float = 0.2126 * color.0
        let weightedGreen: Float = 0.7152 * color.1
        let weightedBlue: Float = 0.0722 * color.2
        let luminance: CGFloat = CGFloat(weightedRed + weightedGreen + weightedBlue)
        var lightBrightness: CGFloat = brightness
        if luminance > 0.5 {
            let factor: CGFloat = max(0.55, 0.5 / luminance)
            lightBrightness = brightness * factor
        }
        let light = NSColor(
            hue: hue,
            saturation: min(saturation, 0.82),
            brightness: min(lightBrightness, 0.8),
            alpha: 1
        )
        let dark = NSColor(
            hue: hue,
            saturation: min(saturation, 0.62),
            brightness: max(brightness, 0.82),
            alpha: 1
        )
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    /// For full-picture icons: the parts whose brightness stands out from
    /// the icon's median brightness.
    private static func brightnessMask(
        from source: Bitmap,
        rowMin: [Int],
        rowMax: [Int],
        colMin: [Int],
        colMax: [Int],
        rim: Int
    ) -> [Float] {
        let side = source.side
        var mask = [Float](repeating: 0, count: side * side)
        var inside: [(index: Int, brightness: Float)] = []

        for y in 0..<side where rowMin[y] >= 0 {
            let firstX = rowMin[y] + rim
            let lastX = rowMax[y] - rim
            guard firstX <= lastX else { continue }
            for x in firstX...lastX {
                guard colMin[x] >= 0, y >= colMin[x] + rim, y <= colMax[x] - rim else { continue }
                let color = source.color(x, y)
                let red: Float = 0.299 * color.0
                let green: Float = 0.587 * color.1
                let blue: Float = 0.114 * color.2
                let brightness: Float = red + green + blue
                inside.append((y * side + x, brightness))
            }
        }

        guard !inside.isEmpty else { return mask }

        let sorted = inside.map(\.brightness).sorted()
        let medianBrightness = sorted[sorted.count / 2]
        for entry in inside {
            let deviation: Float = abs(entry.brightness - medianBrightness)
            mask[entry.index] = smoothstep(0.08, 0.3, deviation)
        }
        return mask
    }

    /// Recenters the mark and scales it to fill the frame, with a small
    /// margin. Nil when the mask is empty.
    private static func cropToContent(_ mask: [Float], side: Int) -> [Float]? {
        var minX = side
        var maxX = -1
        var minY = side
        var maxY = -1

        for y in 0..<side {
            for x in 0..<side where mask[y * side + x] > 0.2 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }

        let contentSide: Int = max(maxX - minX, maxY - minY) + 1
        let padded: Float = Float(contentSide) * 1.08
        let centerX: Float = Float(minX + maxX) / 2
        let centerY: Float = Float(minY + maxY) / 2
        let scale: Float = padded / Float(side)
        let half: Float = Float(side) / 2
        var result = [Float](repeating: 0, count: side * side)

        // Bilinear resample of the square around the mark.
        for y in 0..<side {
            for x in 0..<side {
                let offsetX: Float = Float(x) + 0.5 - half
                let offsetY: Float = Float(y) + 0.5 - half
                let sourceX: Float = centerX + offsetX * scale - 0.5
                let sourceY: Float = centerY + offsetY * scale - 0.5
                let x0: Int = Int(sourceX.rounded(.down))
                let y0: Int = Int(sourceY.rounded(.down))
                let fractionX: Float = sourceX - Float(x0)
                let fractionY: Float = sourceY - Float(y0)

                func value(_ px: Int, _ py: Int) -> Float {
                    guard px >= 0, px < side, py >= 0, py < side else { return 0 }
                    return mask[py * side + px]
                }

                let upper: Float = value(x0, y0) * (1 - fractionX) + value(x0 + 1, y0) * fractionX
                let lower: Float = value(x0, y0 + 1) * (1 - fractionX) + value(x0 + 1, y0 + 1) * fractionX
                result[y * side + x] = upper * (1 - fractionY) + lower * fractionY
            }
        }
        return result
    }

    /// A black image whose alpha is the mask: a template.
    private static func makeImage(fromMask mask: [Float], side: Int) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for index in 0..<(side * side) {
            bytes[index * 4 + 3] = UInt8(max(0, min(255, (mask[index] * 255).rounded())))
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    // MARK: - Small math

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let t = max(0, min(1, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private static func median(of colors: [(Float, Float, Float)]) -> (Float, Float, Float) {
        guard !colors.isEmpty else { return (0, 0, 0) }
        let reds = colors.map(\.0).sorted()
        let greens = colors.map(\.1).sorted()
        let blues = colors.map(\.2).sorted()
        let middle = colors.count / 2
        return (reds[middle], greens[middle], blues[middle])
    }

    // MARK: - Pixels

    /// The icon drawn into a small RGBA buffer, top row first.
    private struct Bitmap {
        let side: Int
        private let bytes: [UInt8]

        init?(image: NSImage, side: Int) {
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
            else { return nil }

            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

            guard let data = context.data else { return nil }
            let buffer = UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: UInt8.self),
                count: side * side * 4
            )
            self.side = side
            self.bytes = Array(buffer)
        }

        func alpha(_ x: Int, _ y: Int) -> Float {
            Float(bytes[(y * side + x) * 4 + 3]) / 255
        }

        /// Straight (un-premultiplied) color, each channel 0...1.
        func color(_ x: Int, _ y: Int) -> (Float, Float, Float) {
            let offset = (y * side + x) * 4
            let alpha = Float(bytes[offset + 3])
            guard alpha > 0 else { return (0, 0, 0) }
            return (
                min(1, Float(bytes[offset]) / alpha),
                min(1, Float(bytes[offset + 1]) / alpha),
                min(1, Float(bytes[offset + 2]) / alpha)
            )
        }
    }
}

#if DEBUG
extension SidebarIconGlyph {
    /// Writes an icon and its glyph side by side as PNGs under
    /// `<checkout>/.docky-dev-glyphs/`, to judge the extraction by eye.
    static func dumpForInspection(source image: NSImage, glyph: NSImage, key: String) {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Sidebar
            .deletingLastPathComponent() // Views
            .deletingLastPathComponent() // Docky
            .deletingLastPathComponent() // checkout
            .appendingPathComponent(".docky-dev-glyphs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let name = key.replacingOccurrences(of: "/", with: "_")
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        if let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            write(source, to: directory.appendingPathComponent("\(name).source.png"))
        }
        var glyphRect = CGRect(x: 0, y: 0, width: side, height: side)
        if let result = glyph.cgImage(forProposedRect: &glyphRect, context: nil, hints: nil) {
            write(result, to: directory.appendingPathComponent("\(name).glyph.png"))
        }
    }

    private static func write(_ image: CGImage, to url: URL) {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
#endif

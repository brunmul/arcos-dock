//
//  SidebarIconTrim.swift
//  Docky
//
//  An app's own icon, stripped of what macOS draws around it for the Dock:
//  the drop shadow under the plate and the empty margin around it. What is
//  left is the plate alone, edge to edge, so a column of icons stays flat
//  and quiet next to the website icons.
//
//  The plate is found as the box of the icon's nearly opaque pixels. When
//  it fills that box the way a rounded square does, the icon is cropped to
//  the box and clipped to a rounded square, which cuts the shadow away.
//  An icon of another shape (an old free-form icon) is only cropped, with
//  its faint pixels, the shadow among them, cleared.
//

import AppKit
import CoreGraphics

enum SidebarIconTrim {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        return cache
    }()

    /// Working size, in pixels. Sharp at the sidebar's sizes on Retina.
    private static let side = 128

    static func forget(key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    /// The icon without shadow or margin; the icon itself when it could
    /// not be read.
    static func trimmed(_ image: NSImage, key: String) -> NSImage {
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        let result = makeTrimmed(image) ?? image
        cache.setObject(result, forKey: key as NSString)
        return result
    }

    private static func makeTrimmed(_ image: NSImage) -> NSImage? {
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = makeContext()
        else { return nil }

        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)

        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            bytes[(y * side + x) * 4 + 3]
        }

        // Box of the nearly opaque pixels: the plate, without its shadow.
        var minX = side, maxX = -1, minY = side, maxY = -1
        var opaqueCount = 0
        for y in 0..<side {
            for x in 0..<side where alpha(x, y) > 230 {
                opaqueCount += 1
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY else { return nil }

        let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        let boxArea = Int(box.width * box.height)
        // A rounded square fills about 95% of its box; a free-form icon
        // much less.
        let isPlate = Double(opaqueCount) / Double(max(boxArea, 1)) > 0.85

        if !isPlate {
            // Clear the faint pixels (the shadow, the glow) and keep the rest.
            for index in 0..<(side * side) where bytes[index * 4 + 3] < 140 {
                bytes[index * 4] = 0
                bytes[index * 4 + 1] = 0
                bytes[index * 4 + 2] = 0
                bytes[index * 4 + 3] = 0
            }
        }

        guard let cleaned = context.makeImage(), let output = makeContext() else { return nil }

        // The bitmap's rows and CGImage cropping both count from the top.
        let crop = CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height)
        guard let cropped = cleaned.cropping(to: crop) else { return nil }

        let target = CGRect(x: 0, y: 0, width: side, height: side)
        output.interpolationQuality = .high
        if isPlate {
            // Slightly inside the plate's own edge, so its rim and the
            // shadow just outside it are both cut away.
            let inset = target.insetBy(dx: -1, dy: -1)
            let path = CGPath(
                roundedRect: target,
                cornerWidth: CGFloat(side) * 0.225,
                cornerHeight: CGFloat(side) * 0.225,
                transform: nil
            )
            output.addPath(path)
            output.clip()
            output.draw(cropped, in: inset)
        } else {
            output.draw(cropped, in: target)
        }

        guard let result = output.makeImage() else { return nil }
        return NSImage(cgImage: result, size: NSSize(width: side, height: side))
    }

    private static func makeContext() -> CGContext? {
        CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

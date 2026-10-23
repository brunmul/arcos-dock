//
//  SidebarPalette.swift
//  Docky
//
//  The sidebar's palette and its wavy separator.
//  The look borrows from Claude's own interface, on Docky's layout: a warm
//  paper surface, a clay accent, a serif for the one line that speaks to
//  the person, and a hand-drawn wave where a rule would be.
//

import AppKit
import SwiftUI

// MARK: - Palette

enum SidebarPalette {
    /// The clay accent, used sparingly: the shortcut numbers and little
    /// else.
    static let clay = Color(red: 0.851, green: 0.467, blue: 0.341)

    /// The sidebar's surface: warm paper in light mode, warm charcoal in
    /// dark mode, in place of the system's neutral greys.
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return NSColor(srgbRed: 0.122, green: 0.118, blue: 0.114, alpha: 1)
        }
        return NSColor(srgbRed: 0.961, green: 0.957, blue: 0.929, alpha: 1)
    })
}

// MARK: - Wave

/// A thin wavy line in place of a straight separator.
struct SidebarWave: View {
    var body: some View {
        SidebarWaveShape()
            .stroke(
                Color.primary.opacity(0.16),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
            )
            .frame(height: 5)
            .accessibilityHidden(true)
    }
}

private struct SidebarWaveShape: Shape {
    private static let wavelength: CGFloat = 9
    private static let amplitude: CGFloat = 1.3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0 else { return path }

        let midY = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: midY))
        var x = rect.minX
        while x <= rect.maxX {
            let phase = (x - rect.minX) / Self.wavelength * 2 * .pi
            path.addLine(to: CGPoint(x: x, y: midY + sin(phase) * Self.amplitude))
            x += 1
        }
        return path
    }
}

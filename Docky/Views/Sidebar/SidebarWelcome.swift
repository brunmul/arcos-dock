//
//  SidebarWelcome.swift
//  Docky
//
//  What makes the sidebar feel like the front of an operating system and
//  not a list of apps: a greeting at the top.
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

// MARK: - Welcome

/// The greeting, following the time of day and the system's language
/// (French or English). Refreshed every minute.
struct SidebarWelcome: View {
    /// Inline, beside the header's buttons, it keeps its full size and
    /// asks for its whole width; on a line of its own, it may shrink a
    /// little to stay on one line.
    var isInline = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(SidebarGreeting.text(at: context.date))
                .font(.system(size: 19, weight: .regular, design: .serif))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(isInline ? 1 : 0.75)
                .fixedSize(horizontal: isInline, vertical: false)
        }
    }
}

enum SidebarGreeting {
    private static var isFrench: Bool {
        Locale.preferredLanguages.first?.hasPrefix("fr") == true
    }

    /// The account's first name, or nothing when it cannot be read.
    private static var firstName: String {
        NSFullUserName()
            .split(separator: " ")
            .first
            .map(String.init) ?? ""
    }

    static func text(at date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let greeting: String
        switch hour {
        case 5..<12:
            greeting = isFrench ? "Bonjour" : "Good morning"
        case 12..<18:
            greeting = isFrench ? "Bon après-midi" : "Good afternoon"
        default:
            greeting = isFrench ? "Bonsoir" : "Good evening"
        }

        let name = firstName
        return name.isEmpty ? greeting : "\(greeting), \(name)"
    }
}

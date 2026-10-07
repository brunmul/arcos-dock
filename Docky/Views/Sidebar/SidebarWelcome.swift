//
//  SidebarWelcome.swift
//  Docky
//
//  What makes the sidebar feel like the front of an operating system and
//  not a list of apps: the Apple mark, a greeting, the date and the time.
//  The look borrows from Claude's own interface, on Docky's layout: a warm
//  paper surface, a clay accent, a serif for the one line that speaks to
//  the person, and a hand-drawn wave where a rule would be.
//

import AppKit
import SwiftUI

// MARK: - Palette

enum SidebarPalette {
    /// The clay accent, used sparingly: the Apple mark and little else.
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

/// Greeting, date and time. Refreshed every minute; the greeting follows
/// the time of day and the system's language (French or English).
struct SidebarWelcome: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 3) {
                Text(SidebarGreeting.text(at: context.date))
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(SidebarGreeting.dateText(for: context.date))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(SidebarGreeting.timeText(for: context.date))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The time alone, for the compact rail.
struct SidebarRailClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(SidebarGreeting.timeText(for: context.date))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
                .help(SidebarGreeting.dateText(for: context.date))
        }
    }
}

/// The Apple mark in clay. It opens System Settings, the nearest thing to
/// the Apple menu a click can reach.
struct SidebarAppleMark: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        } label: {
            Image(systemName: "apple.logo")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SidebarPalette.clay)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("System Settings")
        .accessibilityLabel("System Settings")
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

    /// The language the person set for the system. `Locale.current`
    /// follows the languages Docky itself is translated into, which would
    /// put an English date under a French greeting.
    private static var locale: Locale {
        Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
    }

    /// "Mercredi 7 octobre", in the system's language.
    static func dateText(for date: Date) -> String {
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func timeText(for date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }
}

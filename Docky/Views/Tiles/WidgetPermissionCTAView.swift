//
//  WidgetPermissionCTAView.swift
//  Docky
//

import SwiftUI

/// Call-to-action shown in place of a widget's content while its underlying
/// permission is missing. Widget-tied permissions (calendar, reminders,
/// location) are never requested automatically on render. The OS prompt
/// fires only when the user taps this view's button. Only the button is
/// interactive; the rest of the tile stays inert.
///
/// The layout adapts to the available size: at 1-up / thumbnail scale it
/// collapses to icon + button, and at wider spans (or when expanded) it also
/// shows a one-line reason.
struct WidgetPermissionCTAView: View {
    let permission: Permission
    /// Either `.notDetermined` (button fires the OS prompt) or `.denied`
    /// (macOS won't re-prompt, so the button deep-links to System Settings).
    let status: PermissionStatus
    let renderedSpan: TileSpan
    var isExpanded: Bool = false
    /// Foreground colour for the icon/text. Weather draws on a coloured
    /// gradient (white); calendar/reminders draw on the window background
    /// (primary).
    var foreground: Color = .primary

    @ObservedObject private var permissions = PermissionsService.shared

    private var showsReason: Bool {
        isExpanded || renderedSpan != .one
    }

    var body: some View {
        GeometryReader { proxy in
            let minSide = max(min(proxy.size.width, proxy.size.height), 1)
            let iconSize = min(max(minSide * (isExpanded ? 0.16 : 0.24), 16), isExpanded ? 40 : 30)
            let reasonSize = min(max(minSide * 0.11, 10), 14)
            let spacing = min(max(minSide * 0.06, 4), 12)

            if !isExpanded, proxy.size.height < 60 {
                // Short dock: icon, reason and button stacked do not fit in
                // ~40pt, and the button was the part that got clipped. Show
                // only the button, with the icon inside it.
                let compactSize = min(max(proxy.size.height * 0.28, 9), 13)

                Button {
                    performAction()
                } label: {
                    HStack(spacing: compactSize * 0.4) {
                        Image(systemName: iconName)
                        if renderedSpan != .one {
                            Text(buttonTitle)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .font(.system(size: compactSize, weight: .semibold))
                    .foregroundStyle(foreground.opacity(0.9))
                    .padding(.horizontal, compactSize * 0.9)
                    .padding(.vertical, compactSize * 0.55)
                    .background(
                        Capsule().fill(foreground.opacity(0.16))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(reasonText)
                .padding(.horizontal, 6)
                .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
            VStack(spacing: spacing) {
                Image(systemName: iconName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(foreground.opacity(0.92))
                    .symbolRenderingMode(.hierarchical)

                if showsReason {
                    Text(reasonText)
                        .font(.system(size: reasonSize, weight: .medium))
                        .foregroundStyle(foreground.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    performAction()
                } label: {
                    Text(buttonTitle)
                        .font(.system(size: reasonSize, weight: .semibold))
                        .foregroundStyle(foreground.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, reasonSize * 0.9)
                        .padding(.vertical, reasonSize * 0.5)
                        .background(
                            Capsule().fill(foreground.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(min(max(minSide * 0.1, 8), 20))
            .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func performAction() {
        switch status {
        case .denied:
            permissions.openSystemSettings(for: permission)
        case .notDetermined, .granted:
            Task {
                _ = await permissions.requestPermission(for: permission)
            }
        }
    }

    private var buttonTitle: String {
        switch status {
        case .denied:
            return "Open Settings"
        case .notDetermined, .granted:
            return enableTitle
        }
    }

    private var enableTitle: String {
        switch permission {
        case .location: return "Enable Location"
        case .calendar: return "Enable Calendar"
        case .reminders: return "Enable Reminders"
        default: return "Enable Access"
        }
    }

    private var reasonText: String {
        switch permission {
        case .location: return "Show local weather in the dock."
        case .calendar: return "Show your upcoming events."
        case .reminders: return "Show your open tasks."
        default: return permission.explanation
        }
    }

    private var iconName: String {
        switch permission {
        case .location: return "location.fill"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        default: return "lock.fill"
        }
    }
}

//
//  ClaudeActivityWidgetTileView.swift
//  Docky
//
//  Dock tile and hover panel for what Claude Code is doing on this Mac. The
//  tile shows one headline (project on the first line, current step on the
//  second); the hover panel lists every local Claude Code session, says
//  plainly that nothing else from Claude is shown, and holds the button
//  that connects Claude Code. Data comes from `ClaudeActivityService`.
//

import AppKit
import SwiftUI

struct ClaudeActivityWidgetTileView: View {
    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool
    var isExpanded: Bool = false
    var isExpandedPreviewOpen: Bool = false

    @ObservedObject private var activity = ClaudeActivityService.shared

    /// Claude's terracotta, used for the "working" mark.
    private static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        GeometryReader { proxy in
            ZStack {
                Color.clear

                if !isWithinStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }

                if isExpanded {
                    expandedPanel(size: proxy.size)
                } else {
                    tileContent(size: proxy.size)
                }
            }
            .dockyWidgetGlass(cornerRadius: cornerRadius)
        }
        .opacity(isExpandedPreviewOpen && !isExpanded ? 0.5 : 1)
        .animation(.easeOut(duration: 0.12), value: isExpandedPreviewOpen)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task {
            activity.start()
        }
    }

    // MARK: - Tile

    /// Same two-line grid as the calendar tile: text sized off the dock
    /// height so it stays readable on a small dock.
    private func tileContent(size: CGSize) -> some View {
        let height = max(size.height, 1)
        let minSide = max(min(size.width, height), 1)
        let verticalPadding = max(3, height * 0.09)
        let rowSpacing = max(1, height * 0.03)
        let rowHeight = max(0, (height - verticalPadding * 2 - rowSpacing) / 2)
        let titleFontSize = min(rowHeight * 0.74, 15)
        let headline = activity.headline
        let state = headline?.state ?? .idle

        return HStack(spacing: max(4, titleFontSize * 0.5)) {
            stateMark(state, size: renderedSpan == .one ? titleFontSize * 1.5 : titleFontSize * 1.15)

            if renderedSpan != .one {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    Text(headline?.title ?? "Claude Code")
                        .font(.system(size: titleFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(height: rowHeight)

                    Text(headline?.detail ?? "No session on this Mac")
                        .font(.system(size: titleFontSize * 0.86, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(height: rowHeight)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, renderedSpan == .one ? 0 : max(7, minSide * 0.2))
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: renderedSpan == .one ? .center : .leading)
        .accessibilityElement(children: .combine)
    }

    /// A pulsing spark while Claude works, a yellow bubble when it waits
    /// for an answer, a grey spark otherwise.
    @ViewBuilder
    private func stateMark(_ state: ClaudeCodeSessionActivity.State, size: CGFloat) -> some View {
        switch state {
        case .working:
            Image(systemName: "sparkle")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Self.accent)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityLabel("Working")
        case .waiting:
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Color.yellow)
                .accessibilityLabel("Waiting for you")
        case .idle:
            Image(systemName: "sparkle")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Idle")
        }
    }

    // MARK: - Hover panel

    private func expandedPanel(size: CGSize) -> some View {
        let base = min(max(min(size.width, size.height) * 0.058, 11), 14)

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: base) {
                sectionTitle("Claude Code on this Mac", base: base)

                if !activity.isClaudeCodeConnected {
                    Text("Connect Claude Code to see each step of the sessions running on this Mac.")
                        .font(.system(size: base * 0.9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    panelButton("Connect Claude Code", base: base) {
                        activity.connectClaudeCode()
                    }
                } else if activity.sessions.isEmpty {
                    Text("No Claude Code session yet.")
                        .font(.system(size: base * 0.9))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activity.sessions) { session in
                        sessionRow(session, base: base)
                    }
                }

                if let error = activity.connectionError {
                    Text(error)
                        .font(.system(size: base * 0.85))
                        .foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Only Claude Code sessions run on this Mac show here. Chats and tasks in the Claude app or on the web report nothing to Docky.")
                    .font(.system(size: base * 0.85))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if activity.isClaudeCodeConnected {
                    panelButton("Disconnect Claude Code", base: base * 0.9) {
                        activity.disconnectClaudeCode()
                    }
                    .padding(.top, base * 0.3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(base * 1.3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sectionTitle(_ title: String, base: CGFloat) -> some View {
        Text(title)
            .font(.system(size: base * 0.8, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
            .textCase(.uppercase)
    }

    private func sessionRow(_ session: ClaudeCodeSessionActivity, base: CGFloat) -> some View {
        HStack(alignment: .top, spacing: base * 0.6) {
            stateMark(session.state, size: base)
                .frame(width: base * 1.2)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.system(size: base, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !session.prompt.isEmpty {
                    Text(session.prompt)
                        .font(.system(size: base * 0.9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(statusLine(for: session))
                    .font(.system(size: base * 0.9, weight: .medium))
                    .foregroundStyle(session.state == .idle ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }

    private func statusLine(for session: ClaudeCodeSessionActivity) -> String {
        switch session.state {
        case .working:
            return session.step.isEmpty ? "Working" : session.step
        case .waiting:
            return session.step.isEmpty ? "Needs your answer" : session.step
        case .idle:
            return "Finished"
        }
    }

    private func panelButton(_ title: String, base: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: base, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, base)
                .padding(.vertical, base * 0.5)
                .background(Capsule().fill(.quaternary))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

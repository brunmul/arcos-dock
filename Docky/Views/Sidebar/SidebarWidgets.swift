//
//  SidebarWidgets.swift
//  Docky
//
//  Widgets in the sidebar. Each one is a single row with the height and
//  type of an open app's row: an icon, one line of text, a short figure or
//  a control on the right. There is no unfolded form. The detail (the view
//  the dock strip shows in its hover panel) appears next to the sidebar
//  while the pointer rests on the row, and stays as long as the pointer is
//  on the row or on the detail itself.
//
//  In the compact rail the same widgets are icon tiles with the same hover
//  detail.
//

import AppKit
import SwiftUI

// MARK: - Entry point

/// One widget, as a row (full sidebar) or an icon tile (compact rail).
struct SidebarWidgetItem: View {
    let widget: WidgetTile
    var isRail = false

    var body: some View {
        switch widget.kind {
        case .calendar, .calendarDate:
            SidebarCalendarWidget(widget: widget, isRail: isRail)
        case .nowPlaying:
            SidebarNowPlayingWidget(widget: widget, isRail: isRail)
        case .systemStatus:
            SidebarSystemStatusWidget(widget: widget, isRail: isRail)
        case .claudeActivity:
            SidebarClaudeWidget(widget: widget, isRail: isRail)
        case .reminders:
            SidebarWidgetShell(widget: widget, isRail: isRail, systemName: "checklist", title: widget.title)
        case .batteries:
            SidebarWidgetShell(widget: widget, isRail: isRail, systemName: "battery.75percent", title: widget.title)
        case .weather:
            SidebarWidgetShell(widget: widget, isRail: isRail, systemName: "cloud.sun", title: widget.title)
        case .search:
            SidebarWidgetShell(widget: widget, isRail: isRail, systemName: "magnifyingglass", title: widget.title)
        case .photoFrame:
            SidebarWidgetShell(widget: widget, isRail: isRail, systemName: "photo", title: widget.title)
        case .external:
            SidebarWidgetShell(widget: widget, isRail: isRail, systemName: "square.grid.2x2", title: widget.title)
        }
    }
}

// MARK: - Shell

/// The frame every widget shares: the row or tile, its hover state, and the
/// link to the hover detail. A widget supplies its icon, its line of text
/// and what sits on the right.
private struct SidebarWidgetShell<Trailing: View>: View {
    let widget: WidgetTile
    let isRail: Bool
    let systemName: String
    var iconColor: Color?
    var pulses = false
    let title: String
    var isDimmed = false
    var action: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    @State private var isHovered = false
    @State private var anchor = SidebarAnchorBox()

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                action?()
            }
            .onHover { hovering in
                isHovered = hovering
                SidebarWidgetHoverController.shared.rowHoverChanged(
                    widget: widget,
                    isHovered: hovering,
                    anchor: anchor.screenFrame
                )
            }
            .background(SidebarAnchorView(box: anchor))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
    }

    @ViewBuilder
    private var content: some View {
        if isRail {
            icon(size: 14)
                .frame(maxWidth: .infinity)
                .frame(height: SidebarMetrics.tileHeight)
                .background(SidebarItemBackground(
                    isHovered: isHovered,
                    isCurrent: false,
                    restingOpacity: 0.07,
                    cornerRadius: SidebarMetrics.tileCornerRadius
                ))
        } else {
            HStack(spacing: SidebarMetrics.rowSpacing) {
                icon(size: 12)
                    .frame(width: SidebarMetrics.rowIconSize)

                Text(title)
                    .font(.system(size: SidebarMetrics.rowFontSize))
                    .foregroundStyle(isDimmed ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                trailing()
            }
            .padding(.leading, SidebarMetrics.rowPadding)
            .padding(.trailing, 6)
            .frame(height: SidebarMetrics.rowHeight)
            .background(SidebarItemBackground(isHovered: isHovered, isCurrent: false, restingOpacity: 0.06))
        }
    }

    @ViewBuilder
    private func icon(size: CGFloat) -> some View {
        let image = Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(iconColor ?? Color.secondary)
        if pulses {
            image.symbolEffect(.pulse, options: .repeating)
        } else {
            image
        }
    }
}

extension SidebarWidgetShell where Trailing == EmptyView {
    init(
        widget: WidgetTile,
        isRail: Bool,
        systemName: String,
        iconColor: Color? = nil,
        pulses: Bool = false,
        title: String,
        isDimmed: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.widget = widget
        self.isRail = isRail
        self.systemName = systemName
        self.iconColor = iconColor
        self.pulses = pulses
        self.title = title
        self.isDimmed = isDimmed
        self.action = action
        self.trailing = { EmptyView() }
    }
}

/// Small grey text at the right end of a widget row: a time, a rate.
private struct SidebarWidgetFigure: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Calendar

/// The next event and when it starts. A camera joins its video call; an
/// orange count flags invitations waiting for an answer.
private struct SidebarCalendarWidget: View {
    let widget: WidgetTile
    let isRail: Bool

    @ObservedObject private var calendar = CalendarService.shared

    private var allowedCalendarIDs: Set<String> {
        Set(widget.settings.stringList("calendar.calendarIDs") ?? [])
    }

    private var events: [CalendarEventSnapshot] {
        let allowed = allowedCalendarIDs
        guard !allowed.isEmpty else { return calendar.upcomingEvents }
        return calendar.upcomingEvents.filter { allowed.contains($0.calendarIdentifier) }
    }

    /// The next timed event, or the next all-day one when nothing is timed.
    private var nextEvent: CalendarEventSnapshot? {
        let events = events
        return events.first { !$0.isAllDay } ?? events.first
    }

    private var invitationCount: Int {
        let allowed = allowedCalendarIDs
        guard !allowed.isEmpty else { return calendar.pendingInvitations.count }
        return calendar.pendingInvitations.filter { allowed.contains($0.calendarIdentifier) }.count
    }

    var body: some View {
        Group {
            if calendar.permissionStatus != .granted {
                SidebarWidgetShell(
                    widget: widget,
                    isRail: isRail,
                    systemName: "calendar",
                    title: "Enable Calendar",
                    isDimmed: true,
                    action: {
                        Task {
                            _ = await calendar.requestAccess()
                        }
                    }
                )
            } else if let event = nextEvent {
                SidebarWidgetShell(
                    widget: widget,
                    isRail: isRail,
                    systemName: "calendar",
                    iconColor: Color(nsColor: event.color),
                    title: event.title,
                    action: { event.openInCalendar() },
                    trailing: { trailing(for: event) }
                )
            } else {
                SidebarWidgetShell(
                    widget: widget,
                    isRail: isRail,
                    systemName: "calendar",
                    title: "No upcoming events",
                    isDimmed: true,
                    trailing: { invitationBadge }
                )
            }
        }
        .task {
            calendar.ensureFreshEvent()
        }
    }

    @ViewBuilder
    private func trailing(for event: CalendarEventSnapshot) -> some View {
        HStack(spacing: 4) {
            invitationBadge

            SidebarWidgetFigure(text: timeText(for: event))

            if let url = event.quickJoinURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 16)
                        .background(Capsule().fill(Color.green))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Join the call")
            }
        }
    }

    @ViewBuilder
    private var invitationBadge: some View {
        if invitationCount > 0 {
            Text("\(invitationCount)")
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 15, minHeight: 15)
                .background(Capsule().fill(Color.orange))
                .help("Invitations waiting for an answer")
        }
    }

    /// The start time today, the weekday for another day.
    private func timeText(for event: CalendarEventSnapshot) -> String {
        let isToday = Calendar.current.isDateInToday(event.startDate)
        if event.isAllDay {
            return isToday ? "today" : event.startDate.formatted(.dateTime.weekday(.abbreviated))
        }
        if isToday {
            return event.startDate.formatted(date: .omitted, time: .shortened)
        }
        return event.startDate.formatted(.dateTime.weekday(.abbreviated))
    }
}

// MARK: - Now Playing

private struct SidebarNowPlayingWidget: View {
    let widget: WidgetTile
    let isRail: Bool

    @ObservedObject private var mediaPlayback = MediaPlaybackService.shared

    private var bundleIdentifier: String {
        if let configured = widget.settings.string(NowPlayingWidgetSettings.appBundleIdentifierKey),
           !configured.isEmpty {
            return configured
        }
        return widget.ownerBundleIdentifier
    }

    private var state: MediaPlaybackState? {
        mediaPlayback.state(for: bundleIdentifier)
    }

    private var hasContent: Bool {
        state?.hasContent == true
    }

    private var title: String {
        guard let state, state.hasContent else { return "Not Playing" }
        return state.title.isEmpty ? state.displayName : state.title
    }

    private var isPlaying: Bool {
        state?.isPlaying == true
    }

    var body: some View {
        SidebarWidgetShell(
            widget: widget,
            isRail: isRail,
            systemName: isPlaying ? "waveform" : "music.note",
            title: title,
            isDimmed: !hasContent,
            action: nil,
            trailing: {
                SidebarRowButton(
                    systemName: isPlaying ? "pause.fill" : "play.fill",
                    help: isPlaying ? "Pause" : "Play"
                ) {
                    let target = bundleIdentifier
                    Task {
                        await mediaPlayback.pressPlayPauseButton(for: target)
                    }
                }
            }
        )
    }
}

// MARK: - System status

/// How full the internal disk is, and the network rates. CPU and memory
/// are in the hover detail.
private struct SidebarSystemStatusWidget: View {
    let widget: WidgetTile
    let isRail: Bool

    @ObservedObject private var systemStatus = SystemStatusService.shared

    var body: some View {
        Group {
            if let snapshot = systemStatus.snapshot {
                SidebarWidgetShell(
                    widget: widget,
                    isRail: isRail,
                    systemName: "internaldrive",
                    iconColor: diskColor(for: snapshot.diskUsagePercent),
                    title: "SSD \(Int(snapshot.diskUsagePercent.rounded()))%",
                    trailing: {
                        SidebarWidgetFigure(
                            text: "↓\(snapshot.compactReceivedRateText) ↑\(snapshot.compactSentRateText)"
                        )
                    }
                )
            } else {
                SidebarWidgetShell(
                    widget: widget,
                    isRail: isRail,
                    systemName: "internaldrive",
                    title: "System",
                    isDimmed: true
                )
            }
        }
        .task {
            systemStatus.ensureFreshStatus()
        }
    }

    /// Grey while there is room, orange when the disk is getting full, red
    /// when it is nearly out of space.
    private func diskColor(for percent: Double) -> Color? {
        if percent >= 95 {
            return .red
        }
        if percent >= 85 {
            return .orange
        }
        return nil
    }
}

// MARK: - Claude

private struct SidebarClaudeWidget: View {
    let widget: WidgetTile
    let isRail: Bool

    @ObservedObject private var activity = ClaudeActivityService.shared

    /// Claude's terracotta, used while a session is working.
    private static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)

    private var state: ClaudeCodeSessionActivity.State {
        activity.headline?.state ?? .idle
    }

    var body: some View {
        SidebarWidgetShell(
            widget: widget,
            isRail: isRail,
            systemName: state == .waiting ? "exclamationmark.bubble.fill" : "sparkle",
            iconColor: iconColor,
            pulses: state == .working,
            title: activity.headline?.title ?? "Claude",
            isDimmed: activity.headline == nil,
            action: { ClaudeActivityService.shared.openClaudeDesktop() },
            trailing: {
                SidebarWidgetFigure(text: stateText)
            }
        )
        .task {
            activity.start()
        }
    }

    private var iconColor: Color? {
        switch state {
        case .working: Self.accent
        case .waiting: .yellow
        case .idle: nil
        }
    }

    private var stateText: String {
        switch state {
        case .working: "working"
        case .waiting: "needs you"
        case .idle: activity.headline == nil ? "idle" : "done"
        }
    }
}

// MARK: - Hover detail

/// Remembers the AppKit view behind a row, to place the hover detail next
/// to it on screen.
final class SidebarAnchorBox {
    weak var view: NSView?

    var screenFrame: CGRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

private struct SidebarAnchorView: NSViewRepresentable {
    let box: SidebarAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}

/// Shows a widget's detailed view in a small panel beside the sidebar
/// while the pointer is on the widget's row, and keeps it there while the
/// pointer is on the panel, so its buttons can be used.
final class SidebarWidgetHoverController {
    static let shared = SidebarWidgetHoverController()

    private var panel: NSPanel?
    private var shownWidgetIdentifier: String?
    private var hoveredRowIdentifier: String?
    private var isPanelHovered = false
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?

    /// Time the pointer may spend between the row and the panel.
    private let hideGrace: TimeInterval = 0.25
    private static let gap: CGFloat = 10
    private static let cornerRadius: CGFloat = 14

    private init() {}

    /// The panel's frame while it is showing, so the auto-hiding sidebar
    /// stays up while the pointer is on the detail.
    var visibleFrame: CGRect? {
        guard let panel, panel.isVisible else { return nil }
        return panel.frame
    }

    func rowHoverChanged(widget: WidgetTile, isHovered: Bool, anchor: CGRect?) {
        guard widget.kind.isExpandable else { return }

        if isHovered {
            hoveredRowIdentifier = widget.identifier
            hideWork?.cancel()
            hideWork = nil
            guard shownWidgetIdentifier != widget.identifier, let anchor else { return }

            showWork?.cancel()
            // Already showing another widget's detail: switch at once, the
            // way a menu bar does once one menu is open.
            let delay = panel?.isVisible == true ? 0 : DockyPreferences.shared.widgetHoverPreviewDelay
            let work = DispatchWorkItem { [weak self] in
                self?.show(widget: widget, anchor: anchor)
            }
            showWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            guard hoveredRowIdentifier == widget.identifier else { return }
            hoveredRowIdentifier = nil
            showWork?.cancel()
            showWork = nil
            scheduleHide()
        }
    }

    func panelHoverChanged(_ isHovered: Bool) {
        isPanelHovered = isHovered
        if isHovered {
            hideWork?.cancel()
            hideWork = nil
        } else {
            scheduleHide()
        }
    }

    func hide() {
        showWork?.cancel()
        showWork = nil
        hideWork?.cancel()
        hideWork = nil
        shownWidgetIdentifier = nil
        isPanelHovered = false
        panel?.orderOut(nil)
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hoveredRowIdentifier == nil, !self.isPanelHovered else { return }
            self.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hideGrace, execute: work)
    }

    private func show(widget: WidgetTile, anchor: CGRect) {
        guard hoveredRowIdentifier == widget.identifier else { return }

        let panel = panel ?? makePanel()
        self.panel = panel

        let size = Self.detailSize(for: widget.kind)
        let hostingView = SidebarFirstMouseHostingView(
            rootView: SidebarWidgetDetail(widget: widget, size: size, cornerRadius: Self.cornerRadius)
        )
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let bounds = (screen?.visibleFrame ?? anchor).insetBy(dx: 8, dy: 8)
        var origin = CGPoint(
            x: (SidebarWindowController.shared.panelMaxX ?? anchor.maxX) + Self.gap,
            y: anchor.midY - size.height / 2
        )
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        origin.x = min(origin.x, bounds.maxX - size.width)

        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        shownWidgetIdentifier = widget.identifier
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = SidebarDetailPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = DockyPreferences.shared.windowSpaceBehavior
            .collectionBehavior(includesFullScreenAuxiliary: false)
        return panel
    }

    private static func detailSize(for kind: WidgetKind) -> CGSize {
        switch kind {
        case .calendar:
            CGSize(width: 320, height: 300)
        case .nowPlaying:
            CGSize(width: 340, height: 150)
        case .systemStatus:
            CGSize(width: 280, height: 196)
        case .claudeActivity:
            CGSize(width: 300, height: 220)
        default:
            CGSize(width: 300, height: 240)
        }
    }
}

/// Never key, so the detail does not pull focus from the app in use.
private final class SidebarDetailPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Accepts the first click even though its panel is never key.
private final class SidebarFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// The widget's detailed view on the sidebar's own opaque surface.
private struct SidebarWidgetDetail: View {
    let widget: WidgetTile
    let size: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        WidgetTileView(
            tile: widget,
            cornerRadius: cornerRadius,
            renderedSpan: .four,
            isWithinStack: false,
            isExpanded: true,
            isExpandedPreviewOpen: true
        )
        .frame(width: size.width, height: size.height)
        .background(SidebarChrome())
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onHover { hovering in
            SidebarWidgetHoverController.shared.panelHoverChanged(hovering)
        }
    }
}

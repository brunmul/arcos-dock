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
    /// Set under the greeting: a line of text matching the date and time,
    /// with no icon (the events widget only).
    var isInline = false

    var body: some View {
        switch widget.kind {
        case .calendar, .calendarDate:
            SidebarCalendarWidget(widget: widget, isRail: isRail, isInline: isInline)
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
            SidebarWeatherWidget(widget: widget, isRail: isRail)
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
    /// For a short title that must never be cut ("SSD 89%"): what is on
    /// the right gives way instead.
    var keepsTitleWhole = false
    var action: (() -> Void)?
    var isInline = false
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
        } else if isInline {
            // Same type as the date and time above it, set apart as a small
            // card: a soft background, and a bar of the calendar's color on
            // its left edge, where the color marks without having to be read.
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(iconColor ?? Color.secondary)
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .padding(.trailing, 8)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isDimmed ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                trailing()
            }
            .padding(.leading, 5)
            .padding(.trailing, 5)
            .frame(height: 30)
            .background(SidebarItemBackground(isHovered: isHovered, isCurrent: false, restingOpacity: 0.06, cornerRadius: 8))
        } else {
            HStack(spacing: 0) {
                icon(size: 12)
                    .frame(width: SidebarMetrics.rowIconSize)
                    .padding(.trailing, SidebarMetrics.rowSpacing)

                Text(title)
                    .font(.system(size: SidebarMetrics.rowFontSize))
                    .foregroundStyle(isDimmed ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: keepsTitleWhole, vertical: false)
                    .layoutPriority(keepsTitleWhole ? 1 : 0)

                Spacer(minLength: 6)

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
        action: (() -> Void)? = nil,
        isInline: Bool = false
    ) {
        self.widget = widget
        self.isRail = isRail
        self.systemName = systemName
        self.iconColor = iconColor
        self.pulses = pulses
        self.title = title
        self.isDimmed = isDimmed
        self.action = action
        self.isInline = isInline
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

/// The next event and how long until it starts ("in 25 min"), in the
/// text color, where it reads best (the calendar's color stays on the
/// icon); an orange count flags invitations waiting for an answer.
private struct SidebarCalendarWidget: View {
    let widget: WidgetTile
    let isRail: Bool
    var isInline = false

    @ObservedObject private var calendar = CalendarService.shared

    private var allowedCalendarIDs: Set<String> {
        Set(widget.settings.stringList("calendar.calendarIDs") ?? [])
    }

    /// The person's own events: holidays, the clock change and birthdays
    /// are left out.
    private var events: [CalendarEventSnapshot] {
        let allowed = allowedCalendarIDs
        let own = calendar.upcomingEvents.filter { !$0.isInformational }
        guard !allowed.isEmpty else { return own }
        return own.filter { allowed.contains($0.calendarIdentifier) }
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
                    title: calendar.permissionStatus == .denied ? "Allow Calendar in Settings" : "Enable Calendar",
                    isDimmed: true,
                    action: enableCalendar,
                    isInline: isInline
                )
            } else if let event = nextEvent {
                // Redrawn every minute, so the countdown stays right.
                TimelineView(.everyMinute) { context in
                    SidebarWidgetShell(
                        widget: widget,
                        isRail: isRail,
                        systemName: "calendar",
                        iconColor: Color(nsColor: event.color),
                        title: event.title,
                        action: { event.openInCalendar() },
                        isInline: isInline,
                        trailing: { trailing(for: event, now: context.date) }
                    )
                }
            } else {
                SidebarWidgetShell(
                    widget: widget,
                    isRail: isRail,
                    systemName: "calendar",
                    title: "No upcoming events",
                    isDimmed: true,
                    isInline: isInline,
                    trailing: { invitationBadge }
                )
            }
        }
        .task {
            calendar.ensureFreshEvent()
        }
    }

    /// macOS asks only once: after a refusal the request returns false
    /// without a prompt, so the row opens the Calendars pane instead.
    private func enableCalendar() {
        calendar.refreshAuthorizationStatus()
        if calendar.permissionStatus == .denied {
            PermissionsService.shared.openSystemSettings(for: .calendar)
            return
        }
        Task {
            if await !calendar.requestAccess() {
                await MainActor.run {
                    PermissionsService.shared.openSystemSettings(for: .calendar)
                }
            }
        }
    }

    @ViewBuilder
    private func trailing(for event: CalendarEventSnapshot, now: Date) -> some View {
        HStack(spacing: 4) {
            invitationBadge

            Text(countdown(for: event, now: now))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, isInline ? 6 : 0)
                .padding(.vertical, isInline ? 2 : 0)
                .background {
                    if isInline {
                        Capsule().fill(Color.primary.opacity(0.08))
                    }
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

    private static var isFrench: Bool {
        Locale.preferredLanguages.first?.hasPrefix("fr") == true
    }

    /// How long until the event: "in 25 min", "in 1 h 10", "now" while it
    /// runs; past today, its day; an all-day event, "today" or its day.
    private func countdown(for event: CalendarEventSnapshot, now: Date) -> String {
        let french = Self.isFrench
        let locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
        let day = event.startDate.formatted(.dateTime.weekday(.abbreviated).locale(locale))
        if event.isAllDay {
            return Calendar.current.isDateInToday(event.startDate) ? (french ? "aujourd'hui" : "today") : day
        }
        if event.startDate <= now {
            return french ? "en cours" : "now"
        }
        let minutes = Int(ceil(event.startDate.timeIntervalSince(now) / 60))
        if minutes < 60 {
            return french ? "dans \(minutes) min" : "in \(minutes) min"
        }
        if minutes < 12 * 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            let text = rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))"
            return french ? "dans \(text)" : "in \(text)"
        }
        if Calendar.current.isDateInTomorrow(event.startDate) {
            return french ? "demain" : "tomorrow"
        }
        return Calendar.current.isDateInToday(event.startDate)
            ? event.startDate.formatted(date: .omitted, time: .shortened)
            : day
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
/// The weather where the Mac is: the sky's symbol, the place, and the
/// temperature on the right; the full forecast opens beside on hover.
/// Location is asked for only when the row is clicked, never on its own.
private struct SidebarWeatherWidget: View {
    let widget: WidgetTile
    let isRail: Bool

    @ObservedObject private var weather = WeatherService.shared

    var body: some View {
        Group {
            if !weather.hasLocationAuthorization {
                SidebarWidgetShell(
                    widget: widget,
                    isRail: isRail,
                    systemName: "location",
                    title: "Enable Weather",
                    isDimmed: true,
                    action: {
                        Task {
                            _ = await weather.requestAccess()
                        }
                    }
                )
            } else if let snapshot = weather.snapshot {
                SidebarWidgetShell(
                    widget: widget,
                    isRail: isRail,
                    systemName: snapshot.symbolName,
                    title: snapshot.locationName.isEmpty ? snapshot.conditionDescription : snapshot.locationName,
                    action: { weather.openInWeatherApp() },
                    trailing: { SidebarWidgetFigure(text: snapshot.roundedTemperatureText) }
                )
            } else {
                SidebarWidgetShell(
                    widget: widget,
                    isRail: isRail,
                    systemName: "cloud.sun",
                    title: "Weather",
                    isDimmed: true
                )
            }
        }
        .task {
            weather.ensureFreshWeather()
        }
    }
}

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
                    keepsTitleWhole: true,
                    trailing: {
                        // Both rates where they fit, the download alone
                        // when they are both long.
                        ViewThatFits(in: .horizontal) {
                            SidebarWidgetFigure(
                                text: "↓\(snapshot.compactReceivedRateText) ↑\(snapshot.compactSentRateText)"
                            )
                            SidebarWidgetFigure(text: "↓\(snapshot.compactReceivedRateText)")
                        }
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

/// Claude Code sessions on this Mac, and nothing else from Claude: chats
/// and cloud tasks report nothing Docky can read.
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
            title: activity.headline?.title ?? "Claude Code",
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
        case .idle:
            if !activity.isClaudeCodeConnected {
                "not connected"
            } else {
                activity.headline == nil ? "no session" : "done"
            }
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
    /// Details pinned as windows of their own, by widget: they stay open
    /// where they are, can be dragged anywhere, and close with their ×.
    private var pinnedPanels: [String: NSPanel] = [:]

    /// Time the pointer may spend between the row and the panel.
    private let hideGrace: TimeInterval = 0.25
    private static let gap: CGFloat = 8
    /// Close to a macOS menu's: the detail reads as a menu off the bar,
    /// not as a card.
    private static let cornerRadius: CGFloat = 8

    private init() {}

    /// The panel's frame while it is showing, so the auto-hiding sidebar
    /// stays up while the pointer is on the detail.
    var visibleFrame: CGRect? {
        guard let panel, panel.isVisible else { return nil }
        return panel.frame
    }

    func rowHoverChanged(widget: WidgetTile, isHovered: Bool, anchor: CGRect?) {
        guard widget.kind.isExpandable else { return }
        // Already pinned open: hovering its row adds nothing.
        guard pinnedPanels[widget.identifier] == nil else { return }

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

    // MARK: Pinning

    /// Turns the detail on screen into a window of its own, where it is.
    func pin(_ widget: WidgetTile) {
        guard pinnedPanels[widget.identifier] == nil else { return }
        let (hostingView, size) = Self.makeDetailView(for: widget, isPinned: true)
        let frame = (shownWidgetIdentifier == widget.identifier ? panel?.frame : nil)
            ?? CGRect(origin: NSEvent.mouseLocation, size: size)
        hide()

        let pinned = makePanel()
        pinned.level = .floating
        pinned.isMovable = true
        pinned.isMovableByWindowBackground = true
        pinned.contentView = hostingView
        pinned.setFrame(frame, display: true)
        pinned.orderFrontRegardless()
        pinnedPanels[widget.identifier] = pinned
    }

    func unpin(_ widget: WidgetTile) {
        pinnedPanels.removeValue(forKey: widget.identifier)?.orderOut(nil)
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

        let (hostingView, size) = Self.makeDetailView(for: widget, isPinned: false)
        panel.contentView = hostingView

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let bounds = (screen?.visibleFrame ?? anchor).insetBy(dx: 8, dy: 8)
        var origin: CGPoint
        if let barTop = SidebarWindowController.shared.panelMaxY {
            // The bar is along the bottom: the detail opens above it.
            origin = CGPoint(x: anchor.midX - size.width / 2, y: barTop + Self.gap)
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        } else {
            origin = CGPoint(
                x: (SidebarWindowController.shared.panelMaxX ?? anchor.maxX) + Self.gap,
                y: anchor.midY - size.height / 2
            )
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
            origin.x = min(origin.x, bounds.maxX - size.width)
        }

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

    /// The detail's view and its size. The compact pages are as tall as
    /// their rows, so a short list leaves no empty space below it.
    private static func makeDetailView(for widget: WidgetTile, isPinned: Bool) -> (NSView, CGSize) {
        var size = detailSize(for: widget.kind)
        let fitsContent = SidebarWidgetDetail.hasCompactPage(widget.kind)
        let detail = SidebarWidgetDetail(
            widget: widget,
            size: size,
            fitsContent: fitsContent,
            cornerRadius: cornerRadius,
            isPinned: isPinned
        )
        if fitsContent {
            // Measured apart: a hosting view with no sizing options reports
            // no fitting size, which left the panel zero points tall.
            let measured = NSHostingController(rootView: detail)
                .sizeThatFits(in: CGSize(width: size.width, height: .greatestFiniteMagnitude))
            if measured.height >= 40 {
                size.height = min(size.height, ceil(measured.height))
            }
        }
        let hostingView = SidebarFirstMouseHostingView(rootView: detail)
        hostingView.sizingOptions = []
        return (hostingView, size)
    }

    /// The compact pages' width, and the most they may grow to.
    private static func detailSize(for kind: WidgetKind) -> CGSize {
        switch kind {
        case .calendar, .calendarDate, .nowPlaying, .systemStatus, .weather:
            CGSize(width: 248, height: 320)
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

/// The widget's detail on the sidebar's own opaque surface. The common
/// widgets get a compact page in the manner of Notion: a small grey title,
/// then rows of a grey label and its value, in the sidebar's type, with
/// thin neutral bars instead of large gauges. The others keep the dock's
/// expanded tile.
private struct SidebarWidgetDetail: View {
    let widget: WidgetTile
    let size: CGSize
    /// As tall as its rows rather than `size.height`.
    var fitsContent = false
    let cornerRadius: CGFloat
    /// Pinned: a window of its own, closed with ×. Otherwise the hover
    /// detail, with a pin to keep it open.
    let isPinned: Bool

    @ObservedObject private var sidebar = SidebarPreferences.shared
    @State private var isButtonHovered = false

    static func hasCompactPage(_ kind: WidgetKind) -> Bool {
        switch kind {
        case .systemStatus, .calendar, .calendarDate, .weather, .nowPlaying: true
        default: false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch widget.kind {
        case .systemStatus:
            SidebarStatusDetail()
        case .calendar, .calendarDate:
            SidebarAgendaDetail(widget: widget)
        case .weather:
            SidebarWeatherDetail()
        case .nowPlaying:
            SidebarPlayingDetail(widget: widget)
        default:
            WidgetTileView(
                tile: widget,
                cornerRadius: cornerRadius,
                renderedSpan: .four,
                isWithinStack: false,
                isExpanded: true,
                isExpandedPreviewOpen: true
            )
        }
    }

    var body: some View {
        content
        .frame(width: size.width, height: fitsContent ? nil : size.height)
        .fixedSize(horizontal: false, vertical: fitsContent)
        .background(sidebar.theme.secondarySurface)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                if isPinned {
                    SidebarWidgetHoverController.shared.unpin(widget)
                } else {
                    SidebarWidgetHoverController.shared.pin(widget)
                }
            } label: {
                Image(systemName: isPinned ? "xmark" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isButtonHovered ? .primary : .secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(isButtonHovered ? 0.16 : 0.08))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isButtonHovered = $0 }
            .help(isPinned ? "Close" : "Keep Open in a Window")
            .padding(5)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .sidebarThemeScheme(sidebar.theme)
        .onHover { hovering in
            if !isPinned {
                SidebarWidgetHoverController.shared.panelHoverChanged(hovering)
            }
        }
    }
}

// MARK: - Compact details

/// A detail page: a small grey title (with an optional note beside it),
/// then its rows.
private struct SidebarDetailPage<Content: View>: View {
    let title: String
    var note: String = ""
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 20, alignment: .center)
            .padding(.trailing, 22) // room for the pin

            content()
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One property row: a grey label, then the value, as in a Notion page.
private struct SidebarDetailRow<Value: View>: View {
    let label: String
    var labelWidth: CGFloat = 64
    var action: (() -> Void)?
    @ViewBuilder let value: () -> Value

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(isHovered && action != nil ? 0.07 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .onHover { isHovered = $0 }
    }
}

private struct SidebarDetailText: View {
    let text: String
    var isStrong = true

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: isStrong ? .medium : .regular))
            .monospacedDigit()
            .foregroundStyle(isStrong ? .primary : .secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// A thin neutral bar for a share, red only once it runs high.
private struct SidebarDetailBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(fraction >= 0.85 ? Color.red.opacity(0.75) : Color.primary.opacity(0.45))
                    .frame(width: max(3, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(width: 54, height: 3)
    }
}

// Performance

private struct SidebarStatusDetail: View {
    @ObservedObject private var status = SystemStatusService.shared

    var body: some View {
        SidebarDetailPage(title: "Performance") {
            if let snapshot = status.snapshot {
                usage("CPU", snapshot.cpuUsagePercent)
                usage(
                    "Memory", snapshot.memoryUsagePercent,
                    note: "\(Self.bytes(snapshot.usedMemoryBytes, .memory)) / \(Self.bytes(snapshot.totalMemoryBytes, .memory))"
                )
                if let gpu = snapshot.gpuUsagePercent {
                    usage("GPU", gpu)
                }
                if snapshot.diskTotalBytes > 0 {
                    usage("SSD", snapshot.diskUsagePercent, note: "\(Self.bytes(snapshot.diskFreeBytes, .file)) free")
                }
                SidebarDetailRow(label: "Network") {
                    HStack(spacing: 10) {
                        SidebarDetailText(text: "↓ \(Self.rate(snapshot.receivedBytesPerSecond))")
                        SidebarDetailText(text: "↑ \(Self.rate(snapshot.sentBytesPerSecond))")
                    }
                }
            } else {
                SidebarDetailRow(label: "") { SidebarDetailText(text: "Reading…", isStrong: false) }
            }
        }
        .task { status.ensureFreshStatus() }
    }

    private func usage(_ label: String, _ percent: Double, note: String = "") -> some View {
        SidebarDetailRow(label: label) {
            HStack(spacing: 8) {
                SidebarDetailText(text: "\(Int(percent.rounded()))%")
                    .frame(width: 34, alignment: .leading)
                SidebarDetailBar(fraction: percent / 100)
                if !note.isEmpty {
                    SidebarDetailText(text: note, isStrong: false)
                }
            }
        }
    }

    private static func bytes(_ value: UInt64, _ style: ByteCountFormatter.CountStyle) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: style)
    }

    private static func rate(_ value: Double) -> String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .file))/s"
    }
}

// Agenda

private struct SidebarAgendaDetail: View {
    let widget: WidgetTile

    @ObservedObject private var calendar = CalendarService.shared

    private var events: [CalendarEventSnapshot] {
        let allowed = Set(widget.settings.stringList("calendar.calendarIDs") ?? [])
        let all = calendar.upcomingEvents.filter { !$0.isInformational }
        return Array((allowed.isEmpty ? all : all.filter { allowed.contains($0.calendarIdentifier) }).prefix(6))
    }

    private static var locale: Locale {
        Locale(identifier: Locale.preferredLanguages.first ?? "en")
    }

    var body: some View {
        SidebarDetailPage(title: "Agenda") {
            if events.isEmpty {
                SidebarDetailRow(label: "") { SidebarDetailText(text: "No upcoming events", isStrong: false) }
            }
            ForEach(Array(events.enumerated()), id: \.element.eventIdentifier) { index, event in
                if index == 0 || !Calendar.current.isDate(event.startDate, inSameDayAs: events[index - 1].startDate) {
                    // The sidebar's wave between two days, so each day
                    // reads as its own block.
                    if index > 0 {
                        SidebarWave()
                            .padding(.horizontal, 6)
                            .padding(.top, 7)
                            .padding(.bottom, 1)
                    }
                    Text(dayTitle(event.startDate))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.top, 2)
                        .frame(height: 18, alignment: .bottom)
                }
                SidebarDetailRow(label: timeText(event), labelWidth: 40, action: { event.openInCalendar() }) {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color(nsColor: event.color))
                            .frame(width: 3, height: 14)
                        SidebarDetailText(text: event.title)
                    }
                }
            }
        }
        .task { calendar.ensureFreshEvent() }
    }

    private func dayTitle(_ date: Date) -> String {
        let french = Self.locale.identifier.hasPrefix("fr")
        if Calendar.current.isDateInToday(date) { return french ? "Aujourd'hui" : "Today" }
        if Calendar.current.isDateInTomorrow(date) { return french ? "Demain" : "Tomorrow" }
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Self.locale))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func timeText(_ event: CalendarEventSnapshot) -> String {
        if event.isAllDay { return Self.locale.identifier.hasPrefix("fr") ? "Jour" : "All day" }
        return event.startDate.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Self.locale))
    }
}

// Weather

private struct SidebarWeatherDetail: View {
    @ObservedObject private var weather = WeatherService.shared

    var body: some View {
        if let snapshot = weather.snapshot {
            SidebarDetailPage(title: "Weather", note: snapshot.locationName) {
                SidebarDetailRow(label: "Now", action: { weather.openInWeatherApp() }) {
                    HStack(spacing: 6) {
                        Image(systemName: snapshot.symbolName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        SidebarDetailText(text: snapshot.roundedTemperatureText)
                        SidebarDetailText(text: snapshot.conditionDescription, isStrong: false)
                    }
                }
                ForEach(snapshot.forecast.prefix(5)) { day in
                    SidebarDetailRow(label: day.weekdayShortText) {
                        HStack(spacing: 8) {
                            Image(systemName: day.symbolName)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            SidebarDetailText(text: Self.degrees(day.lowTemperature), isStrong: false)
                                .frame(width: 30, alignment: .trailing)
                            SidebarDetailText(text: Self.degrees(day.highTemperature))
                                .frame(width: 30, alignment: .leading)
                        }
                    }
                }
            }
            .task { weather.ensureFreshWeather() }
        } else {
            SidebarDetailPage(title: "Weather") {
                SidebarDetailRow(label: "") { SidebarDetailText(text: "Reading…", isStrong: false) }
            }
            .task { weather.ensureFreshWeather() }
        }
    }

    private static func degrees(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°" } ?? "–"
    }
}

// Now playing

private struct SidebarPlayingDetail: View {
    let widget: WidgetTile

    @ObservedObject private var media = MediaPlaybackService.shared

    private var bundleIdentifier: String {
        if let configured = widget.settings.string(NowPlayingWidgetSettings.appBundleIdentifierKey), !configured.isEmpty {
            return configured
        }
        return widget.ownerBundleIdentifier
    }

    var body: some View {
        let state = media.state(for: bundleIdentifier)
        SidebarDetailPage(title: "Now Playing", note: state?.displayName ?? "") {
            HStack(spacing: 10) {
                Group {
                    if let data = state?.artworkData, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.primary.opacity(0.06)
                            .overlay(Image(systemName: "music.note").foregroundStyle(.tertiary))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    SidebarDetailText(text: state?.hasContent == true ? state!.title : "Not Playing")
                    SidebarDetailText(text: state?.artist ?? "", isStrong: false)
                }
                Spacer(minLength: 0)
                control("backward.fill", "Previous") { await media.skipToPrevious(for: $0) }
                control(state?.isPlaying == true ? "pause.fill" : "play.fill", "Play or Pause") { await media.pressPlayPauseButton(for: $0) }
                control("forward.fill", "Next") { await media.skipToNext(for: $0) }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
    }

    private func control(_ symbol: String, _ help: String, _ run: @escaping (String) async -> Void) -> some View {
        let target = bundleIdentifier
        return SidebarRowButton(systemName: symbol, help: help) {
            Task { await run(target) }
        }
    }
}

// MARK: - Secondary surface

extension SidebarTheme {
    /// The theme's second color, in the manner of Slack's: a deeper shade
    /// of the bar for the panels that open off it, so a detail reads as
    /// part of the bar rather than a card laid over the desktop. With the
    /// Claude theme, a slightly deeper paper, or a raised charcoal in dark
    /// mode.
    var secondarySurface: Color {
        if isClaude {
            return Color(nsColor: NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                    return NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 1)
                }
                return NSColor(srgbRed: 0.925, green: 0.918, blue: 0.882, alpha: 1)
            })
        }
        func channel(_ shift: Int) -> Double {
            Double(((top >> shift) & 0xFF) + ((bottom >> shift) & 0xFF)) / 2 / 255
        }
        // Halfway down the gradient, then deeper: a quarter towards black on
        // a dark theme, a touch on a light one.
        let keep = isDark ? 0.75 : 0.92
        return Color(.sRGB, red: channel(16) * keep, green: channel(8) * keep, blue: channel(0) * keep)
    }
}

//
//  SidebarWindowController.swift
//  Docky
//
//  Owns the sidebar panel: a borderless, non-activating window set flush
//  against the left edge of the primary display, from the top of the
//  usable area to the bottom. It is opaque and has no margin or rounded
//  outline of its own, so it reads as part of the screen's frame rather
//  than as a card floating over the desktop, the way Arc's sidebar wraps
//  its page.
//
//  A second, click-through panel sits just to its right and draws two
//  concave corners in the sidebar's color, at the top and the bottom. They
//  round off the area next to the sidebar, so the windows there look set
//  into it.
//
//  Pinned, it stays put. Unpinned, it fades out and comes back when the
//  pointer rests on the left edge, then leaves again shortly after the
//  pointer moves away. It fades in place rather than sliding off screen:
//  with a second display arranged on the left, a slide would travel
//  across that display.
//
//  Set to the bottom (`SidebarPreferences.edge`), the same panel runs along
//  the bottom of the usable area instead, the full width, and the corners
//  panel steps aside: its corners are drawn for a column.
//
//  While the app in front fills the whole screen (a video in full screen,
//  a game, Steam Big Picture, any app in its own full-screen Space), the
//  panel steps out of the way, and comes back when that ends.
//
//  The dock strip (`MainWindow`) still exists while the sidebar is on,
//  because the Launchpad, window switcher and other overlays hang off it.
//  It simply refuses to order in; see `MainWindow.order(_:relativeTo:)`.
//

import AppKit
import Combine
import SwiftUI

final class SidebarWindowController: NSObject {
    static let shared = SidebarWindowController()

    private let preferences = SidebarPreferences.shared
    private var panel: SidebarPanel?
    private var cornersPanel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var pointerTimer: Timer?
    private var isRevealed = true
    private var edgeDwellStart: Date?
    private var awayStart: Date?
    private var fullScreenTimer: Timer?
    /// Out of the way of a full-screen app.
    private(set) var isSteppedAside = false

    /// How long the pointer must rest on the edge before the panel shows,
    /// so crossing to another display does not flash it.
    private let revealDwell: TimeInterval = 0.12
    /// How long the pointer must stay away before the panel hides.
    private let hideDelay: TimeInterval = 0.45
    private let animationDuration: TimeInterval = 0.16

    private override init() {
        super.init()
    }

    // MARK: - Mode

    /// Switches between the sidebar and the dock strip, live.
    func setSidebarMode(_ enabled: Bool) {
        guard preferences.isEnabled != enabled else { return }
        preferences.isEnabled = enabled
        (NSApp.delegate as? AppDelegate)?.applyDockPresentation()
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        let cornersPanel = cornersPanel ?? makeCornersPanel()
        self.cornersPanel = cornersPanel

        applyFrame()
        isRevealed = true
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()

        // A child window is ordered out with its parent and stays right
        // above it, so the corners never outlive or sink under the sidebar.
        cornersPanel.alphaValue = preferences.isBottom ? 0 : 1
        if cornersPanel.parent == nil {
            panel.addChildWindow(cornersPanel, ordered: .above)
        }

        observeInputsIfNeeded()
        updatePointerTracking()
        startFullScreenWatch()
        SidebarSwitcherController.shared.start()
        _ = SidebarBookmarks.shared
    }

    func hide() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        fullScreenTimer?.invalidate()
        fullScreenTimer = nil
        isSteppedAside = false
        SidebarWidgetHoverController.shared.hide()
        SidebarSwitcherController.shared.stop()
        panel?.orderOut(nil)
    }

    /// The strip of screen the sidebar occupies while it is pinned, for the
    /// service that nudges maximized windows out from under Docky. Nil when
    /// the sidebar is off, unpinned, or not on screen.
    var currentReservation: (screen: NSScreen, frame: CGRect)? {
        guard preferences.isEnabled, preferences.isPinned,
              let panel, panel.isVisible,
              let screen = targetScreen() else {
            return nil
        }

        guard let frame = panelFrame() else { return nil }
        return (screen, frame)
    }

    /// Right edge of the sidebar on screen, for the widget detail and the
    /// search that open beside it. Nil while the bar is at the bottom.
    var panelMaxX: CGFloat? {
        guard let panel, panel.isVisible, !preferences.isBottom else { return nil }
        return panel.frame.maxX
    }

    /// Top edge of the bar while it is at the bottom, for the widget
    /// detail that opens above it.
    var panelMaxY: CGFloat? {
        guard let panel, panel.isVisible, preferences.isBottom else { return nil }
        return panel.frame.maxY
    }

    /// The display the sidebar lives on, whether or not it is showing.
    var screen: NSScreen? {
        targetScreen()
    }

    // MARK: - Panel

    private func makePanel() -> SidebarPanel {
        let panel = SidebarPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .mainMenu
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = DockyPreferences.shared.windowSpaceBehavior
            .collectionBehavior(includesFullScreenAuxiliary: false)
        let hostingView = SidebarHostingView(rootView: SidebarView())
        // The panel's frame is ours to decide. Left on, the hosting view
        // widens the window to whatever its content would ideally take.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        return panel
    }

    /// The strip to the right of the sidebar that carries the two concave
    /// corners. It never takes a click: everything in it but the corners is
    /// empty, and what lies under it belongs to other apps.
    private func makeCornersPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .mainMenu
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = DockyPreferences.shared.windowSpaceBehavior
            .collectionBehavior(includesFullScreenAuxiliary: false)
        let hostingView = NSHostingView(rootView: SidebarCornersView())
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        return panel
    }

    private func cornersFrame(besides frame: CGRect) -> CGRect {
        CGRect(
            x: frame.maxX,
            y: frame.minY,
            width: SidebarPreferences.cornerRadius,
            height: frame.height
        )
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }

    private func panelFrame() -> CGRect? {
        guard let screen = targetScreen() else { return nil }
        let visible = screen.visibleFrame
        if preferences.isBottom {
            return CGRect(
                x: visible.minX,
                y: visible.minY,
                width: visible.width,
                height: SidebarPreferences.bottomHeight
            )
        }
        return CGRect(
            x: visible.minX,
            y: visible.minY,
            width: preferences.panelWidth,
            height: visible.height
        )
    }

    private func applyFrame(animated: Bool = false) {
        guard let panel, let frame = panelFrame() else { return }
        let corners = cornersFrame(besides: frame)
        guard animated, panel.isVisible else {
            panel.setFrame(frame, display: true)
            cornersPanel?.setFrame(corners, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            cornersPanel?.animator().setFrame(corners, display: true)
        }
    }

    private func observeInputsIfNeeded() {
        guard cancellables.isEmpty else { return }

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyFrame()
            }
            .store(in: &cancellables)

        // Full sidebar <-> icon rail. `receive(on:)` matters here too:
        // `@Published` fires before the value is stored.
        preferences.$isCompact
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyFrame(animated: true)
            }
            .store(in: &cancellables)

        // Left <-> bottom.
        preferences.$edge
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] edge in
                guard let self else { return }
                SidebarWidgetHoverController.shared.hide()
                self.applyFrame()
                self.cornersPanel?.alphaValue = edge == .bottom ? 0 : (self.isRevealed ? 1 : 0)
            }
            .store(in: &cancellables)

        // Theme or wallpaper option: the desktop picture follows.
        Publishers.CombineLatest(preferences.$themeID.removeDuplicates(), preferences.$matchesWallpaper.removeDuplicates())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, enabled in
                guard let self else { return }
                SidebarWallpaper.apply(self.preferences.theme, enabled: enabled)
            }
            .store(in: &cancellables)

        preferences.$isPinned
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePointerTracking()
            }
            .store(in: &cancellables)
    }

    // MARK: - Full screen

    /// Looks at the app in front twice a second. A window list read costs
    /// little and needs no permission for the frames it reports.
    private func startFullScreenWatch() {
        guard fullScreenTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkFullScreen()
        }
        RunLoop.main.add(timer, forMode: .common)
        fullScreenTimer = timer
    }

    private func checkFullScreen() {
        guard let panel, let screen = targetScreen() else { return }
        let fullScreen = Self.frontAppFillsScreen(screen)
        guard fullScreen != isSteppedAside else { return }
        isSteppedAside = fullScreen

        if fullScreen {
            SidebarWidgetHoverController.shared.hide()
            SidebarSwitcherController.shared.hide()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// True when the frontmost app (not Docky) has an ordinary window that
    /// covers the whole display, menu bar included.
    static func frontAppFillsScreen(_ screen: NSScreen) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return false }

        // Window frames come with the origin at the top left of the
        // primary display.
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return false }
        let target = CGRect(
            x: screen.frame.minX,
            y: primaryHeight - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return false }
            return frame.insetBy(dx: 1, dy: 1).contains(target.insetBy(dx: 2, dy: 2))
                && frame.width <= target.width + 2
        }
    }

    // MARK: - Reveal on the edge

    /// Pinned: no tracking, panel shown. Unpinned: poll the pointer ten
    /// times a second. A timer rather than an event monitor because it
    /// needs no permission and costs next to nothing at this rate.
    private func updatePointerTracking() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        edgeDwellStart = nil
        awayStart = nil

        guard preferences.isEnabled, panel != nil else { return }

        if preferences.isPinned {
            setRevealed(true)
            return
        }

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.pointerTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func pointerTick() {
        guard let panel, let screen = targetScreen() else { return }

        let pointer = NSEvent.mouseLocation
        let now = Date()

        if isRevealed {
            let keepZone = panel.frame.insetBy(dx: -28, dy: -28)
            let isInteracting = NSEvent.pressedMouseButtons != 0
            // A widget's detail opens beside the sidebar; the pointer being
            // on it counts as still using the sidebar.
            let isOnDetail = SidebarWidgetHoverController.shared.visibleFrame?
                .insetBy(dx: -12, dy: -12)
                .contains(pointer) ?? false
            if keepZone.contains(pointer) || isInteracting || isOnDetail {
                awayStart = nil
            } else if let start = awayStart {
                if now.timeIntervalSince(start) >= hideDelay {
                    awayStart = nil
                    setRevealed(false)
                }
            } else {
                awayStart = now
            }
            return
        }

        let edgeZone = preferences.isBottom
            ? CGRect(
                x: screen.visibleFrame.minX,
                y: screen.frame.minY,
                width: screen.visibleFrame.width,
                height: 3
            )
            : CGRect(
                x: screen.frame.minX,
                y: screen.visibleFrame.minY,
                width: 3,
                height: screen.visibleFrame.height
            )
        if edgeZone.contains(pointer) {
            if let start = edgeDwellStart {
                if now.timeIntervalSince(start) >= revealDwell {
                    edgeDwellStart = nil
                    setRevealed(true)
                }
            } else {
                edgeDwellStart = now
            }
        } else {
            edgeDwellStart = nil
        }
    }

    private func setRevealed(_ revealed: Bool) {
        guard let panel, isRevealed != revealed || panel.alphaValue != (revealed ? 1 : 0) else { return }
        isRevealed = revealed
        panel.ignoresMouseEvents = !revealed
        if !revealed {
            SidebarWidgetHoverController.shared.hide()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = revealed ? 1 : 0
            cornersPanel?.animator().alphaValue = revealed && !preferences.isBottom ? 1 : 0
        }
    }
}

/// Never becomes key or main, so clicking the sidebar does not pull focus
/// from the app the user is working in.
private final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Accepts the first click even though the panel is never key; otherwise
/// every button would need two clicks.
private final class SidebarHostingView: NSHostingView<SidebarView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

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
        cornersPanel.alphaValue = 1
        if cornersPanel.parent == nil {
            panel.addChildWindow(cornersPanel, ordered: .above)
        }

        observeInputsIfNeeded()
        updatePointerTracking()
    }

    func hide() {
        pointerTimer?.invalidate()
        pointerTimer = nil
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

        let visible = screen.visibleFrame
        let frame = CGRect(
            x: visible.minX,
            y: visible.minY,
            width: preferences.panelWidth,
            height: visible.height
        )
        return (screen, frame)
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

        preferences.$isPinned
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePointerTracking()
            }
            .store(in: &cancellables)
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
            if keepZone.contains(pointer) || isInteracting {
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

        let edgeZone = CGRect(
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

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = revealed ? 1 : 0
            cornersPanel?.animator().alphaValue = revealed ? 1 : 0
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

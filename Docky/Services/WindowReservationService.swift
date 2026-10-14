//
//  WindowReservationService.swift
//  Docky
//
//  Watches for app windows that get maximized to a screen's visibleFrame
//  and shrinks them via the Accessibility API to leave room for Docky.
//  The macOS 26 system Dock no longer reserves screen space, so apps think
//  visibleFrame is theirs to fill. This service makes Docky behave as if
//  it reserved space — only when the user opts into resizeWindow mode.
//
//  Activation gates: maximizedWindowBehavior == .resizeWindow AND
//  accessibility permission granted. The service piggybacks on
//  WindowRegistry's AX observers (which already track every app's window
//  resizes) rather than spinning up a parallel observer set.
//
//  The pinned sidebar is stricter. It always reserves its strip (given
//  the accessibility permission), and for every window, not only the
//  maximized ones: a column down the left edge covers the part of a window
//  people read first, so nothing is allowed to sit under it. Windows that
//  touch the strip's edge also follow it when the sidebar changes width
//  or goes away. Set along the bottom, it does the same upwards: nothing
//  sits under the bar, and windows resting on it follow it.
//

import AppKit
import Combine
import Foundation

final class WindowReservationService {
    static let shared = WindowReservationService()

    private let preferences = DockyPreferences.shared
    private let permissions = PermissionsService.shared
    private let registry = WindowRegistry.shared
    private let sidebar = SidebarPreferences.shared

    /// The inner edge of the strip the sidebar last reserved: its right
    /// edge down the left side, or its top edge along the bottom; nil on
    /// the side it does not use, or when it reserved nothing. Lets windows
    /// docked against it follow a change.
    private var lastSidebarEdges: (x: CGFloat?, y: CGFloat?) = (nil, nil)
    private var pendingSidebarUpdate: DispatchWorkItem?
    private var pendingRescan: DispatchWorkItem?
    /// What was last asked of each window, and the frame it had then. A
    /// window that refuses the frame (a minimum width, say) is not asked
    /// again until it moves.
    private var lastRequests: [WindowID: (seen: CGRect, target: CGRect)] = [:]

    private var cancellables: Set<AnyCancellable> = []
    private var registrySubscription: AnyCancellable?
    private var windowCooldowns: [WindowID: Date] = [:]
    private let cooldownInterval: TimeInterval = 0.25
    private let matchTolerance: CGFloat = 1
    private let edgeTolerance: CGFloat = 2

    private enum DockSide { case top, bottom, left, right }

    private init() {}

    func start() {
        // `permissions.$accessibility` is still ObservableObject-based,
        // so re-derive both inputs every time either side fires. The
        // Observation read of `preferences.maximizedWindowBehavior`
        // re-runs the closure on its own changes; the Combine .sink
        // handles the permission side.
        observeChanges { [weak self] in
            let mode = DockyPreferences.shared.maximizedWindowBehavior
            let status = PermissionsService.shared.accessibility
            self?.updateActivation(mode: mode, status: status)
        }
        .store(in: &cancellables)

        permissions.$accessibility
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                let mode = DockyPreferences.shared.maximizedWindowBehavior
                self?.updateActivation(mode: mode, status: status)
            }
            .store(in: &cancellables)

        // The sidebar turning on or off, being pinned, or changing width.
        // `receive(on:)` because `@Published` fires before the value is
        // stored.
        Publishers.CombineLatest4(sidebar.$isEnabled, sidebar.$isPinned, sidebar.$isCompact, sidebar.$edge)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let mode = DockyPreferences.shared.maximizedWindowBehavior
                let status = PermissionsService.shared.accessibility
                self?.updateActivation(mode: mode, status: status)
                self?.scheduleSidebarUpdate()
            }
            .store(in: &cancellables)
    }

    private func updateActivation(mode: MaximizedWindowBehavior, status: PermissionStatus) {
        let shouldBeActive = (mode == .resizeWindow || sidebar.isEnabled) && (status == .granted)
        if shouldBeActive {
            attachIfNeeded()
        } else {
            detach()
        }
    }

    private func attachIfNeeded() {
        guard registrySubscription == nil else { return }
        registrySubscription = registry.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows in
                self?.scan(windows: windows)
            }
    }

    private func detach() {
        registrySubscription?.cancel()
        registrySubscription = nil
        windowCooldowns.removeAll()
        lastRequests.removeAll()
        pendingRescan?.cancel()
        pendingRescan = nil
    }

    // MARK: - Sidebar

    /// Runs once the sidebar's panel has settled into its new frame.
    private func scheduleSidebarUpdate() {
        pendingSidebarUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applySidebarEdgeChange()
        }
        pendingSidebarUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Moves the windows docked against the sidebar's old edge to its new
    /// one (wider, narrower, or gone), then clears anything still under it.
    private func applySidebarEdgeChange() {
        let newEdges = currentSidebarEdges()
        guard registrySubscription != nil else {
            lastSidebarEdges = newEdges
            return
        }

        let oldEdges = lastSidebarEdges
        lastSidebarEdges = newEdges

        if let screen = SidebarWindowController.shared.screen,
           let primaryScreenHeight = NSScreen.screens.first?.frame.height {
            let visibleFrame = screen.visibleFrame
            let ownPID = ProcessInfo.processInfo.processIdentifier

            // Each side on its own: moving the bar from the left to the
            // bottom gives the left back and takes the bottom.
            let fromX = oldEdges.x ?? visibleFrame.minX
            let toX = newEdges.x ?? visibleFrame.minX
            let fromY = oldEdges.y ?? visibleFrame.minY
            let toY = newEdges.y ?? visibleFrame.minY
            let movesX = oldEdges.x != nil && abs(fromX - toX) > matchTolerance
            let movesY = oldEdges.y != nil && abs(fromY - toY) > matchTolerance

            if movesX || movesY {
                for window in registry.windows where window.processIdentifier != ownPID && !window.isMinimized {
                    guard let axFrame = window.frame else { continue }
                    let nsFrame = flipY(axFrame, primaryHeight: primaryScreenHeight)
                    guard screenContaining(nsFrame) == screen else { continue }

                    var target = nsFrame
                    if movesX, abs(nsFrame.minX - fromX) < edgeTolerance {
                        target.origin.x = toX
                        target.size.width = nsFrame.maxX - toX
                    }
                    if movesY, abs(nsFrame.minY - fromY) < edgeTolerance {
                        target.origin.y = toY
                        target.size.height = nsFrame.maxY - toY
                    }
                    guard !rectsMatch(target, nsFrame), target.width > 0, target.height > 0 else { continue }
                    registry.resize(window, to: flipY(target, primaryHeight: primaryScreenHeight))
                }
            }
        }

        lastRequests.removeAll()
        scan(windows: registry.windows)
    }

    private func currentSidebarEdges() -> (x: CGFloat?, y: CGFloat?) {
        guard let frame = SidebarWindowController.shared.currentReservation?.frame else { return (nil, nil) }
        return sidebar.isBottom ? (nil, frame.maxY) : (frame.maxX, nil)
    }

    /// Where a window overlapping the sidebar's strip should go. A window
    /// anchored to the screen's edges (maximized, tiled, or flush left)
    /// keeps its right edge and gives up the covered part. A free window
    /// slides right instead, and only shrinks if it would leave the screen.
    private func clearOfSidebar(_ frame: CGRect, strip: CGRect, visible: CGRect) -> CGRect {
        // Along the bottom: the same, upwards.
        if strip.width > strip.height {
            let isAnchored = abs(frame.minY - visible.minY) < edgeTolerance
                || flushEdgeCount(of: frame, against: visible) >= 2
            var result = frame
            result.origin.y = strip.maxY
            if isAnchored {
                result.size.height = frame.maxY - strip.maxY
            } else if result.maxY > visible.maxY {
                result.size.height = visible.maxY - strip.maxY
            }
            return result
        }

        let isAnchored = abs(frame.minX - visible.minX) < edgeTolerance
            || flushEdgeCount(of: frame, against: visible) >= 2

        var result = frame
        result.origin.x = strip.maxX
        if isAnchored {
            result.size.width = frame.maxX - strip.maxX
        } else if result.maxX > visible.maxX {
            result.size.width = visible.maxX - strip.maxX
        }
        return result
    }

    /// Looks again shortly: used while a mouse button is down, so a window
    /// being dragged is not pulled out from under the pointer.
    private func scheduleRescan() {
        guard pendingRescan == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRescan = nil
            guard self.registrySubscription != nil else { return }
            self.scan(windows: self.registry.windows)
        }
        pendingRescan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func scan(windows: [AppWindow]) {
        guard let reservation = currentReservation(),
              let primaryScreenHeight = NSScreen.screens.first?.frame.height
        else { return }
        let dockyScreen = reservation.screen
        let dockyFrame = reservation.frame
        let isSidebar = reservation.isSidebar

        let visibleFrame = dockyScreen.visibleFrame
        guard let dockySide = side(of: dockyFrame, on: visibleFrame) else { return }

        // The sidebar also moves free windows, so it must not act while one
        // is being dragged or resized by hand.
        if isSidebar, NSEvent.pressedMouseButtons != 0 {
            scheduleRescan()
            return
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let now = Date()

        for window in windows where window.processIdentifier != ownPID {
            if let until = windowCooldowns[window.id], now < until { continue }

            guard let axFrame = window.frame else { continue }
            if isSidebar {
                guard !window.isMinimized else { continue }
                let nsFrame = flipY(axFrame, primaryHeight: primaryScreenHeight)
                guard screenContaining(nsFrame) == dockyScreen else { continue }
                // A tall window that stops just short of the sidebar (a few
                // points of desktop showing between them) snaps flush
                // against it, so the concave corners frame it.
                if !nsFrame.intersects(dockyFrame), !sidebar.isBottom {
                    let gap = nsFrame.minX - dockyFrame.maxX
                    let isTall = nsFrame.height >= visibleFrame.height - edgeTolerance * 2
                    guard gap > matchTolerance, gap <= 14, isTall else { continue }
                    var target = nsFrame
                    target.origin.x = dockyFrame.maxX
                    target.size.width = nsFrame.maxX - dockyFrame.maxX
                    if let last = lastRequests[window.id], rectsMatch(last.seen, nsFrame), rectsMatch(last.target, target) {
                        continue
                    }
                    lastRequests[window.id] = (nsFrame, target)
                    if registry.resize(window, to: flipY(target, primaryHeight: primaryScreenHeight)) {
                        windowCooldowns[window.id] = now.addingTimeInterval(cooldownInterval)
                    }
                    continue
                }
                guard nsFrame.intersects(dockyFrame) else { continue }
                // A full-screen window (a game, a video) keeps the whole
                // screen; the sidebar steps aside for it instead.
                guard !nsFrame.insetBy(dx: 1, dy: 1).contains(dockyScreen.frame.insetBy(dx: 2, dy: 2)) else { continue }

                let nsTarget = clearOfSidebar(nsFrame, strip: dockyFrame, visible: visibleFrame)
                guard !rectsMatch(nsFrame, nsTarget), nsTarget.width > 0, nsTarget.height > 0 else { continue }
                if let last = lastRequests[window.id],
                   rectsMatch(last.seen, nsFrame), rectsMatch(last.target, nsTarget) {
                    continue
                }

                lastRequests[window.id] = (nsFrame, nsTarget)
                if registry.resize(window, to: flipY(nsTarget, primaryHeight: primaryScreenHeight)) {
                    windowCooldowns[window.id] = now.addingTimeInterval(cooldownInterval)
                }
                continue
            }

            // WindowRegistry returns AX-space frames (flipped Y, origin at the
            // top-left of the primary display). Convert to NSScreen space
            // before any geometry comparison.
            let nsFrame = flipY(axFrame, primaryHeight: primaryScreenHeight)

            // Only act on windows on the same screen as Docky.
            guard let windowScreen = screenContaining(nsFrame), windowScreen == dockyScreen else { continue }

            // Tile/maximize signature: window intersects Docky AND is anchored
            // to ≥2 edges of the visible frame. This catches full maximize (4
            // flush edges), half tiles (3), and quarter tiles (2) without
            // resizing free-floating windows that happen to overlap Docky.
            guard nsFrame.intersects(dockyFrame) else { continue }
            guard flushEdgeCount(of: nsFrame, against: visibleFrame) >= 2 else { continue }

            // Push the window off Docky's strip.
            let nsTarget = pushAway(nsFrame, from: dockyFrame, on: dockySide)
            // Don't issue redundant resizes.
            guard !rectsMatch(nsFrame, nsTarget) else { continue }
            // Don't shrink a window that has nothing left in the relevant axis.
            guard nsTarget.width > 0, nsTarget.height > 0 else { continue }

            // AX setters take flipped-Y coordinates; convert before applying.
            let axTarget = flipY(nsTarget, primaryHeight: primaryScreenHeight)
            let succeeded = registry.resize(window, to: axTarget)
            if succeeded {
                windowCooldowns[window.id] = now.addingTimeInterval(cooldownInterval)
            }
        }
    }

    /// The strip of screen Docky occupies: the pinned sidebar when that
    /// presentation is on, otherwise the dock strip.
    private func currentReservation() -> (screen: NSScreen, frame: CGRect, isSidebar: Bool)? {
        if let sidebar = SidebarWindowController.shared.currentReservation {
            return (sidebar.screen, sidebar.frame, true)
        }
        guard preferences.maximizedWindowBehavior == .resizeWindow,
              let mainWindow = NSApp.windows.compactMap({ $0 as? MainWindow }).first,
              let screen = mainWindow.screen,
              let frame = mainWindow.currentReservationFrame
        else { return nil }
        return (screen, frame, false)
    }

    /// Flips a rect between AX (top-left origin, Y grows down) and NSScreen
    /// (bottom-left origin, Y grows up) coordinate spaces. The transform is
    /// its own inverse.
    private func flipY(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        // Match by largest intersection so a window straddling a display
        // boundary picks the screen it mostly lives on.
        var best: (screen: NSScreen, area: CGFloat)?
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(frame)
            let area = intersection.width * intersection.height
            if area > 0, area > (best?.area ?? 0) {
                best = (screen, area)
            }
        }
        return best?.screen
    }

    /// Identifies which edge of the visible frame Docky is flush against.
    /// Returns nil when Docky isn't anchored to any edge (corner-floating or
    /// inset by more than the edge tolerance), in which case there's no clean
    /// reservation strip to subtract.
    private func side(of dock: CGRect, on visible: CGRect) -> DockSide? {
        if abs(dock.minX - visible.minX) < edgeTolerance, dock.maxX < visible.maxX - edgeTolerance {
            return .left
        }
        if abs(dock.maxX - visible.maxX) < edgeTolerance, dock.minX > visible.minX + edgeTolerance {
            return .right
        }
        if abs(dock.minY - visible.minY) < edgeTolerance, dock.maxY < visible.maxY - edgeTolerance {
            return .bottom
        }
        if abs(dock.maxY - visible.maxY) < edgeTolerance, dock.minY > visible.minY + edgeTolerance {
            return .top
        }
        return nil
    }

    /// Counts how many of `frame`'s edges sit flush against `visible`. macOS
    /// tile and maximize states leave windows snapped to visible-frame edges,
    /// so this is a cheap classifier for "the user committed this window to a
    /// system-managed slot."
    private func flushEdgeCount(of frame: CGRect, against visible: CGRect) -> Int {
        var count = 0
        if abs(frame.minX - visible.minX) < edgeTolerance { count += 1 }
        if abs(frame.maxX - visible.maxX) < edgeTolerance { count += 1 }
        if abs(frame.minY - visible.minY) < edgeTolerance { count += 1 }
        if abs(frame.maxY - visible.maxY) < edgeTolerance { count += 1 }
        return count
    }

    /// Shrinks `frame` so it no longer overlaps Docky, by advancing the side
    /// of the frame that touches Docky's strip. Other edges are preserved so
    /// half/quarter tiles keep their cross-axis anchoring.
    private func pushAway(_ frame: CGRect, from dock: CGRect, on side: DockSide) -> CGRect {
        var result = frame
        switch side {
        case .left:
            let newMinX = max(frame.minX, dock.maxX)
            result.origin.x = newMinX
            result.size.width = max(0, frame.maxX - newMinX)
        case .right:
            let newMaxX = min(frame.maxX, dock.minX)
            result.size.width = max(0, newMaxX - frame.minX)
        case .bottom:
            let newMinY = max(frame.minY, dock.maxY)
            result.origin.y = newMinY
            result.size.height = max(0, frame.maxY - newMinY)
        case .top:
            let newMaxY = min(frame.maxY, dock.minY)
            result.size.height = max(0, newMaxY - frame.minY)
        }
        return result
    }

    private func rectsMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < matchTolerance
            && abs(a.minY - b.minY) < matchTolerance
            && abs(a.width - b.width) < matchTolerance
            && abs(a.height - b.height) < matchTolerance
    }
}

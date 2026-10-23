//
//  SidebarContextMenu.swift
//  Docky
//
//  Right-click menus for the sidebar's items. Laid over the item, the
//  area is invisible to every event but a right-click (or a Control-click),
//  so AppKit's own hit-testing picks the item under the pointer, and the
//  menu opens at the pointer as any context menu does. Clicks, hovers and
//  drags pass through to the item.
//
//  It replaces, in the sidebar, the dock strip's way of watching every
//  click and matching it against each item's frame, which could open the
//  menu of an item that was not the one under the pointer, in its place.
//

import AppKit
import SwiftUI

struct SidebarContextMenuArea: NSViewRepresentable {
    let actionProvider: (NSEvent.ModifierFlags) -> [ContextAction]

    /// Same call as `ContextActionMenuPresenter`; the menu opens at the
    /// pointer whatever the edge.
    init(
        actionProvider: @escaping (NSEvent.ModifierFlags) -> [ContextAction],
        preferredEdge: NSRectEdge = .maxX
    ) {
        self.actionProvider = actionProvider
    }

    func makeNSView(context: Context) -> AreaView {
        let view = AreaView()
        view.actionProvider = actionProvider
        return view
    }

    func updateNSView(_ nsView: AreaView, context: Context) {
        nsView.actionProvider = actionProvider
    }

    final class AreaView: NSView {
        var actionProvider: (NSEvent.ModifierFlags) -> [ContextAction] = { _ in [] }
        /// Builds the menu and runs its items; kept while the menu is up.
        private var menuBuilder: ContextActionMenuPresenter.Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, Self.isContextClick(event) else { return nil }
            return super.hitTest(point)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func rightMouseDown(with event: NSEvent) {
            showMenu(for: event)
        }

        override func mouseDown(with event: NSEvent) {
            if Self.isContextClick(event) {
                showMenu(for: event)
            } else {
                super.mouseDown(with: event)
            }
        }

        private func showMenu(for event: NSEvent) {
            let actions = actionProvider(event.modifierFlags)
            guard !actions.isEmpty else { return }
            let builder = ContextActionMenuPresenter.Coordinator(
                actionProvider: actionProvider,
                preferredEdge: .maxX,
                onPresentationChanged: { _ in }
            )
            menuBuilder = builder
            let menu = builder.buildMenu(actions: actions)
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        private static func isContextClick(_ event: NSEvent) -> Bool {
            event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }
    }
}

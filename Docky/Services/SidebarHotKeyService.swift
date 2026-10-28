//
//  SidebarHotKeyService.swift
//  Docky
//
//  ⌃⌥1 to ⌃⌥9 open the first nine pinned items of the sidebar, in the
//  order they were arranged by dragging (`SidebarPreferences.pinnedOrder`).
//  While ⌃⌥ is held, each tile shows its number.
//

import AppKit
import Carbon
import Combine

final class SidebarHotKeyService: ObservableObject {
    static let shared = SidebarHotKeyService()

    /// True while ⌃⌥ (and no other modifier) is held: the tiles show
    /// their numbers.
    @Published private(set) var showsNumbers = false

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var hotKeyHandlerRef: EventHandlerRef?
    private var flagsMonitors: [Any] = []
    /// 'SBNK' as four ASCII bytes; the id is the shortcut's number.
    private let signature = OSType(0x53424E4B)

    private static let digitKeyCodes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
    ]

    private init() {
        installHotKeyHandler()
        registerHotKeys()
        watchModifiers()
    }

    /// Every pinned app and site, in their arranged order, super pins first.
    var allPinnedItems: [SidebarPinnedItem] {
        var items: [SidebarPinnedItem] = []
        for tile in TileStore.shared.tiles where tile.id.hasPrefix("pinned:") {
            if case .app(let app) = tile.content, !app.bundleIdentifier.isEmpty {
                items.append(.app(app))
            }
        }
        items += SidebarPreferences.shared.pinnedSites.map(SidebarPinnedItem.site)
        return SidebarPreferences.shared.ordered(items)
    }

    /// The pinned items the shortcuts reach, in shortcut order.
    var numberedItems: [SidebarPinnedItem] {
        Array(allPinnedItems.prefix(Self.digitKeyCodes.count))
    }

    /// The shortcut number of a pinned item, 1 to 9, or nil past the ninth.
    func number(for item: SidebarPinnedItem) -> Int? {
        numberedItems.firstIndex { $0.id == item.id }.map { $0 + 1 }
    }

    private func open(number: Int) {
        let items = numberedItems
        guard number >= 1, number <= items.count else { return }
        switch items[number - 1] {
        case .app(let app):
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
        case .site(let site):
            BrowserTabsService.shared.openOrFocus(site)
        }
    }

    // MARK: - Hotkeys

    private func installHotKeyHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else {
                return OSStatus(eventNotHandledErr)
            }

            let service = Unmanaged<SidebarHotKeyService>.fromOpaque(userData).takeUnretainedValue()
            var firedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &firedID
            )

            guard status == noErr, firedID.signature == service.signature else {
                return OSStatus(eventNotHandledErr)
            }

            let number = Int(firedID.id)
            Task { @MainActor in service.open(number: number) }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )
    }

    private func registerHotKeys() {
        let modifiers = UInt32(controlKey | optionKey)
        for (index, keyCode) in Self.digitKeyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(keyCode),
                modifiers,
                EventHotKeyID(signature: signature, id: UInt32(index + 1)),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
            } else {
                NSLog("Docky: ⌃⌥\(index + 1) is already taken by another app (status \(status))")
            }
        }
    }

    // MARK: - Numbers on the tiles

    /// Follows ⌃⌥ everywhere: the global monitor while another app is in
    /// front (it needs the Accessibility permission the sidebar already
    /// has), the local one while Docky is.
    private func watchModifiers() {
        let update: (NSEvent) -> Void = { [weak self] event in
            let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])
            let held = flags == [.control, .option]
            if self?.showsNumbers != held {
                self?.showsNumbers = held
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: update) {
            flagsMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            update(event)
            return event
        }) {
            flagsMonitors.append(local)
        }
    }
}

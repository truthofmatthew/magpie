import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let store = Store(dir: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Magpie"))
    private lazy var monitor = Monitor(store: store)
    private lazy var model = PanelModel(store: store)
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var keyMonitor: Any?
    private var hotKey: EventHotKeyRef?
    private var countWatcher: AnyCancellable?
    private var aboutWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app; don't start the real clipboard machinery for them.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        store.maxItems = Settings.maxItems
        store.prune()
        monitor.start()
        model.choose = { [weak self] item, mode in self?.choose(item, mode) }

        panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                        backing: .buffered, defer: true)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        let hosting = NSHostingView(rootView: HistoryView(model: model, store: store))
        hosting.sizingOptions = []  // the panel sets its own size; don't let SwiftUI add title bar height
        panel.contentView = hosting

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Magpie")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        countWatcher = store.$items.sink { [weak self] items in
            self?.statusItem.button?.title = items.isEmpty ? "" : "\(items.count)"
            self?.statusItem.button?.setAccessibilityLabel("Magpie, \(items.count) items")
        }
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        registerHotKey()
    }

    /// Opening the app again (Spotlight, Finder) shows the history too.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    // MARK: Hotkey (⌥⌘V)

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            (NSApp.delegate as? AppDelegate)?.togglePanel()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x434C_4950), id: 1)  // "CLIP"
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    // MARK: Panel

    @objc func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        model.query = ""
        model.selection = 0
        model.showCount += 1

        let size = NSSize(width: 460, height: 500)  // matches HistoryView's frame
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let bounds = screen.visibleFrame
        let origin = NSPoint(x: min(max(mouse.x - size.width / 2, bounds.minX), bounds.maxX - size.width),
                             y: min(max(mouse.y - size.height, bounds.minY), bounds.maxY - size.height))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
    }

    private func hidePanel() {
        panel.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        hidePanel()
    }

    /// Returns nil for keys we handled, or the event to let the search field have it.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case kVK_Escape: hidePanel()
        case kVK_DownArrow: model.move(1)
        case kVK_UpArrow: model.move(-1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard let item = model.selected else { return nil }
            choose(item, mods.contains(.command) ? .copy : mods.contains(.shift) ? .pastePlain : .paste)
        case kVK_Delete where mods == .command:
            if let item = model.selected { store.delete(item); model.move(0) }
        case kVK_ANSI_P where mods == .command:
            if let item = model.selected { store.togglePin(item) }
        default:
            if mods == .command, let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(digit) {
                let items = model.visible
                if items.count >= digit { choose(items[digit - 1], .paste) }
                return nil
            }
            return event
        }
        return nil
    }

    private func choose(_ item: Item, _ mode: PasteMode) {
        Pasteboard.write(item, store: store, plainText: mode == .pastePlain)
        monitor.ignoreCurrent()
        store.touch(item)
        hidePanel()
        guard mode != .copy else { return }

        // Opened via the hotkey, the panel never activates this app, so the app you were typing in is
        // still frontmost. Opened via Spotlight it did, so hand focus back first.
        if NSApp.isActive { NSApp.hide(nil) }
        if AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Pasteboard.sendPaste() }
        } else {
            // It's on the clipboard already; this asks once for the permission that lets Enter paste.
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
    }

    // MARK: Menu bar menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let show = menu.addItem(withTitle: "Show Clipboard History", action: #selector(togglePanel), keyEquivalent: "v")
        show.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(.separator())

        // Clicking a menu bar icon doesn't activate this app, so frontmost is the app you were just in.
        let ignored = Settings.ignoredApps
        if let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
           id != Bundle.main.bundleIdentifier {
            let item = menu.addItem(withTitle: "Ignore Copies from \(app.localizedName ?? id)",
                                    action: #selector(toggleIgnored(_:)), keyEquivalent: "")
            item.representedObject = [id, app.localizedName ?? id]
            item.state = ignored[id] != nil ? .on : .off
        }
        if !ignored.isEmpty {
            let submenu = NSMenu()
            for (id, name) in ignored.sorted(by: { $0.value < $1.value }) {
                let item = submenu.addItem(withTitle: name, action: #selector(toggleIgnored(_:)), keyEquivalent: "")
                item.representedObject = [id, name]
                item.state = .on
                item.target = self
            }
            menu.addItem(withTitle: "Ignored Apps", action: nil, keyEquivalent: "").submenu = submenu
        }

        let sizes = NSMenu()
        for size in [25, 50, 100, 250, 500, 1000] {
            let item = sizes.addItem(withTitle: "\(size) Items", action: #selector(setHistorySize(_:)), keyEquivalent: "")
            item.tag = size
            item.state = size == store.maxItems ? .on : .off
            item.target = self
        }
        menu.addItem(withTitle: "Keep Last", action: nil, keyEquivalent: "").submenu = sizes

        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "About Magpie", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Magpie", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApp.terminate(_:)) { item.target = self }
    }

    @objc private func toggleIgnored(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String] else { return }
        var ignored = Settings.ignoredApps
        ignored[pair[0]] = ignored[pair[0]] == nil ? pair[1] : nil
        Settings.ignoredApps = ignored
    }

    @objc private func setHistorySize(_ sender: NSMenuItem) {
        let size = sender.tag
        let extra = store.items.filter { !$0.pinned }.count - size
        if extra > 0 {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Keep only the last \(size) items?"
            alert.informativeText = "This deletes your \(extra) oldest items now. Pinned items are kept."
            alert.addButton(withTitle: "Delete \(extra) Items")
            alert.addButton(withTitle: "Cancel")
            alert.buttons[0].hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Settings.maxItems = size
        store.maxItems = size
        store.prune()
    }

    @objc func showAbout() {
        if aboutWindow == nil {
            let controller = NSHostingController(rootView: AboutView())
            controller.sizingOptions = []  // otherwise SwiftUI resizes it later and adds the title bar height
            let window = NSWindow(contentViewController: controller)
            // Size it now, not lazily, so centering below uses the real size.
            window.setContentSize(controller.sizeThatFits(in: NSSize(width: 430, height: 10_000)))
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "About Magpie"
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            [.miniaturizeButton, .zoomButton].forEach { window.standardWindowButton($0)?.isHidden = true }
            aboutWindow = window
        }
        guard let window = aboutWindow else { return }
        // Dead center of the screen you're on; NSWindow.center() sits a bit above the middle.
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let bounds = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: bounds.midX - window.frame.width / 2,
                                          y: bounds.midY - window.frame.height / 2))
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }

    @objc private func clearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This deletes everything except pinned items. It can't be undone."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn { store.clearUnpinned() }
    }
}

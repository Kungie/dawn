import AppKit
import Combine
import SwiftUI

/// Dawn's own menu bar item and drop-down panel.
///
/// SwiftUI's `MenuBarExtra` keeps its window at the size it first measured and wraps the content in the
/// system's glass frame, so the panel sat too low, left gaps when a banner was missing, and showed glass
/// edges around the black screen. This draws a plain borderless panel instead: pinned under the sun,
/// exactly as tall as its content, and re-pinned whenever the content changes size.
@MainActor
final class StatusPanelController: NSObject {
    private let model: DawnModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hosting: NSHostingController<PanelContainer>
    private let geometry = PanelGeometry()
    private let panel: DawnPanel
    private var sizeObservation: NSKeyValueObservation?
    private var changes: AnyCancellable?
    private var outsideClick: Any?
    private var escapeKey: Any?

    init(model: DawnModel) {
        self.model = model
        hosting = NSHostingController(rootView: PanelContainer(model: model, geometry: geometry))
        hosting.sizingOptions = [.preferredContentSize]
        panel = DawnPanel(contentRect: NSRect(x: 0, y: 0, width: PanelView.width, height: 400),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()

        // The hosting view goes in as a plain content view (not contentViewController), so AppKit never resizes
        // the window by itself from the bottom-left corner; only place() sets the frame, top edge fixed.
        hosting.view.autoresizingMask = [.width, .height]
        panel.contentView = hosting.view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle)
            button.imagePosition = .imageLeading
        }
        updateStatusItem()
        model.closePanel = { [weak self] in self?.hide() }

        // Re-pin the panel whenever SwiftUI reports a new size (Settings opened, a banner came or went).
        sizeObservation = hosting.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.place() }
        }
        // Displays added, removed or rearranged: pin it again under the sun.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.place() }
        }
        // Keep the menu bar text and icon in step with the model.
        changes = model.objectWillChange
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.image(asking: model.ask != nil, done: model.done != nil)
        let text = model.menuBarText.map { " \($0)" } ?? ""
        defer { if panel.isVisible { place() } } // the item can change width, keep the panel centred under it
        button.attributedTitle = MenuBarIcon.title(text)
        button.setAccessibilityLabel(model.menuBarText.map { "Dawn, \($0) left in the window" } ?? "Dawn")
    }

    /// `DAWN_PANEL_SELFTEST=1`: open the panel, change its content, print the frames, quit.
    func selfTest() {
        func log(_ what: String) {
            let f = panel.frame
            let barBottom = statusItem.button?.window?.frame.minY ?? -1
            print(String(format: "%-9@ top %.1f  bottom %.1f  height %.1f  menu bar edge %.1f", what as NSString, f.maxY, f.minY, f.height, barBottom))
        }
        show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { log("main") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            DistributedNotificationCenter.default().postNotificationName(HookCommand.notification, object: nil,
                userInfo: ["message": "Claude needs your permission to use Bash", "project": "selftest"], deliverImmediately: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { log("alert") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { self.model.showSettings = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { log("settings") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { self.model.showSettings = false; self.model.dismissAsk() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { log("back"); exit(0) }
    }

    @objc private func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func show() {
        model.showSettings = false
        hosting.view.layoutSubtreeIfNeeded()
        place()
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem.button?.highlight(true)

        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        escapeKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.hide(); return nil }
            return event
        }
    }

    private func hide() {
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let m = outsideClick { NSEvent.removeMonitor(m) }
        if let m = escapeKey { NSEvent.removeMonitor(m) }
        outsideClick = nil
        escapeKey = nil
        model.dismissDone()
    }

    /// Notch tip a hair under the menu bar, panel centred under the sun and kept inside the screen;
    /// if the panel has to shift to stay on screen, the notch moves so it still points at the sun.
    private func place() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var size = hosting.preferredContentSize
        if size.height < 1 { size = hosting.view.fittingSize }
        size.width = PanelView.width
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.minX + 6), screen.maxX - size.width - 6)
        // The status item's window spans the full menu bar height, so its bottom is the menu bar's edge.
        let top = buttonWindow.frame.minY - 3
        geometry.arrowX = min(max(anchor.midX - x, 16), size.width - 16)
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }
}

/// A borderless panel that can take clicks and key events without activating the app.
final class DawnPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

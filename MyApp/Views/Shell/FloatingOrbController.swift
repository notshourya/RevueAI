import AppKit
import SwiftUI

/// Owns the floating capture orb: a small always-on-top, non-activating
/// borderless panel visible over any app while a capture is running.
/// Click activates RevueAI; right-click offers Stop / Open. Draggable, with
/// its position remembered across sessions.
@MainActor
final class FloatingOrbController {
    private var panel: NSPanel?
    private static let originKey = "floatingOrb.origin"

    static func shouldFloat(state: CaptureCoordinator.State, enabled: Bool) -> Bool {
        enabled && state != .idle
    }

    func update(state: CaptureCoordinator.State, enabled: Bool, coordinator: CaptureCoordinator) {
        if Self.shouldFloat(state: state, enabled: enabled) {
            show(coordinator: coordinator)
        } else {
            hide()
        }
    }

    private func show(coordinator: CaptureCoordinator) {
        guard panel == nil else { return }
        let hosting = NSHostingView(rootView: FloatingOrbContent().environment(coordinator))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        if let stored = UserDefaults.standard.string(forKey: Self.originKey) {
            panel.setFrameOrigin(NSPointFromString(stored))
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 120,
                                         y: screen.visibleFrame.maxY - 120))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func hide() {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
        panel.orderOut(nil)
        self.panel = nil
    }
}

/// The floating panel's SwiftUI content: the orb, click-through to the app,
/// and a stop/open context menu.
private struct FloatingOrbContent: View {
    @Environment(CaptureCoordinator.self) private var coordinator

    var body: some View {
        OrbView(state: OrbState.from(captureState: coordinator.state,
                                     isExtracting: coordinator.isExtracting,
                                     hasError: coordinator.errorMessage != nil),
                size: 84)
            .padding(6)
            .contentShape(Circle())
            .onTapGesture { openMainWindow() }
            .contextMenu {
                Button("Stop & summarize") { Task { await coordinator.stop() } }
                Button("Open RevueAI") { openMainWindow() }
            }
            .help("RevueAI is listening — click to open")
    }

    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows
            .first { $0.identifier?.rawValue.hasPrefix("library") == true }?
            .makeKeyAndOrderFront(nil)
    }
}

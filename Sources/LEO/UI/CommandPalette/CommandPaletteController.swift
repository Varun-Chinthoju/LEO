import AppKit
import SwiftUI

private final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

@MainActor
final class CommandPaletteController: NSObject, ObservableObject {
    private var panel: CommandPalettePanel?
    @Published var text = ""
    @Published var status = ""
    @Published var response = ""
    @Published var isVoiceListening = false
    @Published var voiceAudioLevel = 0.0
    @Published var voicePhase: VoiceSessionPhase = .idle
    private var statusPresenter = StatusPresenter()
    private let onSubmit: (String) -> Void

    init(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
    }

    func show() {
        if panel == nil { createPanel() }
        text = ""
        status = ""
        response = ""
        isVoiceListening = false
        voicePhase = .idle
        voiceAudioLevel = 0
        statusPresenter = StatusPresenter()
        configureInteractivePanel()
        resizePanel(expanded: false)
        positionPanel()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel else { return }
            panel.makeFirstResponder(panel.contentView)
        }
    }

    func hide() {
        isVoiceListening = false
        voiceAudioLevel = 0
        panel?.orderOut(nil)
    }

    func showVoiceListening() {
        showVoicePhase(.listening)
    }

    func showVoicePhase(_ phase: VoiceSessionPhase) {
        if panel == nil { createPanel() }
        text = ""
        status = Self.status(for: phase)
        response = ""
        voicePhase = phase
        isVoiceListening = phase != .idle
        voiceAudioLevel = 0
        statusPresenter = StatusPresenter()
        configureVoiceOverlay()
        resizePanel(expanded: false)
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func apply(_ event: AssistantEvent) {
        let wasExpanded = !response.isEmpty
        if let nextStatus = statusPresenter.present(event) {
            status = nextStatus
        }
        switch event {
        case .responseDelta(let delta):
            response += delta
        case .responseCompleted(let result):
            response = result
        case .failed(let failure):
            response = failure.message
        default:
            break
        }
        if wasExpanded != !response.isEmpty {
            resizePanel(expanded: !response.isEmpty)
        }
    }

    private static func status(for phase: VoiceSessionPhase) -> String {
        switch phase {
        case .idle: return ""
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .responding: return "Responding"
        }
    }

    private func createPanel() {
        let panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 96),
            styleMask: [.borderless, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.center()

        let view = CommandPaletteView(state: self, onSubmit: { [weak self] value in
            self?.prepareForSubmission()
            self?.onSubmit(value)
        }, onClose: { [weak self] in self?.hide() })
        panel.contentView = NSHostingView(rootView: view)
        self.panel = panel
    }

    private func configureInteractivePanel() {
        guard let panel else { return }
        panel.styleMask.remove(.nonactivatingPanel)
        panel.ignoresMouseEvents = false
    }

    private func configureVoiceOverlay() {
        guard let panel else { return }
        panel.styleMask.insert(.nonactivatingPanel)
        panel.ignoresMouseEvents = true
        panel.resignKey()
    }

    private func prepareForSubmission() {
        status = ""
        response = ""
        statusPresenter = StatusPresenter()
        resizePanel(expanded: false)
    }

    private func resizePanel(expanded: Bool) {
        guard let panel else { return }
        let targetHeight: CGFloat = expanded ? 360 : (isVoiceListening ? 122 : 96)
        guard abs(panel.frame.height - targetHeight) > 0.5 else { return }
        var frame = panel.frame
        frame.size.height = targetHeight
        panel.setFrame(frame, display: true, animate: true)
        positionPanel()
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        var frame = panel.frame
        frame.origin.x = visibleFrame.midX - (frame.width / 2)
        frame.origin.y = visibleFrame.minY + 80
        panel.setFrameOrigin(frame.origin)
    }
}

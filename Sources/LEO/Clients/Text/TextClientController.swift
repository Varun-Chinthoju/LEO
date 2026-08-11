import Foundation

@MainActor
final class TextClientController {
    private let orchestrator: InteractionOrchestrator
    private lazy var palette = CommandPaletteController { [weak self] input in
        self?.submit(input)
    }

    init(orchestrator: InteractionOrchestrator = InteractionOrchestrator()) {
        self.orchestrator = orchestrator
    }

    func show() { palette.show() }
    func hide() { palette.hide() }

    func setVoiceListening(_ listening: Bool) {
        setVoicePhase(listening ? .listening : .idle)
    }

    func setVoicePhase(_ phase: VoiceSessionPhase) {
        if phase == .idle { palette.hide() }
        else { palette.showVoicePhase(phase) }
    }

    func setVoiceAudioLevel(_ level: Double) {
        palette.voiceAudioLevel = level
    }

    private func submit(_ input: String) {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let request = AssistantRequest(input: .text(input), source: .commandPalette)
        Task { [weak self] in
            guard let self else { return }
            let events = await orchestrator.submit(request)
            for await event in events { palette.apply(event) }
        }
    }
}

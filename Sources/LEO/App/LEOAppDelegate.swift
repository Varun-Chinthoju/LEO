import AppKit

@MainActor
final class LEOAppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var textClient: TextClientController?
    private var paletteObserver: NSObjectProtocol?
    private var ipcServer: LocalIPCServer?
    private var modelHost: ModelHost?
    private var voiceInput: VoiceInputController?
    private var contextEngine: ContextEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("LEO launch callback")
        ProcessInfo.processInfo.disableAutomaticTermination("LEO menu-bar agent")
        NSApp.setActivationPolicy(.accessory)
        let orchestrator = configuredOrchestrator()
        let contextEngine = ContextEngine(
            observationSource: WorkspaceFrontmostApplicationObservation(),
            browserContextProvider: BrowserContextProvider(source: MacOSBrowserContextSource())
        )
        self.contextEngine = contextEngine
        Task { await contextEngine.startObservingFrontmostApplication() }
        let textClient = TextClientController(orchestrator: orchestrator)
        self.textClient = textClient

        let voiceClient = VoiceClient(
            orchestrator: orchestrator,
            synthesizer: KokoroSpeechSynthesizer(),
            onPhase: { [weak self] phase in
                self?.textClient?.setVoicePhase(phase)
                self?.voiceInput?.setAssistantPhase(phase)
            }
        )
        let voiceInput = VoiceInputController(
            input: AudioInput(backend: AVAudioEngineCaptureBackend()),
            recognizer: ParakeetSpeechRecognizer(),
            voiceClient: voiceClient
        )
        voiceInput.onTranscript = { transcript in
            leoVoiceLogger.info("voice_transcript_received characters=\(transcript.count, privacy: .public)")
            NSLog("LEO transcript: %{public}@", transcript)
        }
        voiceInput.onError = { message in
            leoVoiceLogger.error("voice_error")
            NSLog("LEO voice error: %{public}@", message)
        }
        voiceInput.onVoicePhaseChanged = { [weak self] phase in
            self?.textClient?.setVoicePhase(phase)
            self?.voiceInput?.setAssistantPhase(phase)
        }
        voiceInput.onAudioLevel = { [weak self] level in
            self?.textClient?.setVoiceAudioLevel(level)
        }
        self.voiceInput = voiceInput

        let runtimeDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LEO/runtime", isDirectory: true)
        let ipcServer = LocalIPCServer(runtimeDirectoryURL: runtimeDirectory, orchestrator: orchestrator)
        self.ipcServer = ipcServer
        Task { @MainActor [weak self] in
            do {
                NSLog("LEO starting local IPC")
                try await ipcServer.start()
                NSLog("LEO local IPC ready at %{public}@", ipcServer.socketURL.path)
            } catch {
                NSLog("LEO could not start local IPC server: %{public}@", String(describing: error))
                self?.ipcServer = nil
            }
        }
        paletteObserver = NotificationCenter.default.addObserver(
            forName: .leoShowCommandPalette,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.textClient?.show()
            }
        }

        let hotkeyManager = HotkeyManager(backend: SystemHotkeyBackend())
        hotkeyManager.onEvent = { [weak self] event in
            switch event {
            case .typedCommandPaletteRequested:
                self?.textClient?.show()
            case .voicePushToTalkBegan:
                self?.voiceInput?.toggleCapture()
            case .voicePushToTalkEnded:
                // Voice hotkey is a toggle. Key-up must not stop capture.
                break
            }
        }

        do {
            try hotkeyManager.start()
            self.hotkeyManager = hotkeyManager
        } catch {
            NSLog("LEO could not register global hotkeys: %{public}@", String(describing: error))
        }

        // Request after the app has entered the run loop so the system dialogs
        // are associated with the visible LEO app instead of a transient launch
        // state. Approval remains user-controlled in System Settings.
        DispatchQueue.main.async {
            PermissionAccess.requestHotkeyPermissions()
        }
        Task { @MainActor in
            await PermissionAccess.requestIntegrationPermissions()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stop()
        if let paletteObserver {
            NotificationCenter.default.removeObserver(paletteObserver)
        }
        if let ipcServer {
            Task { await ipcServer.stop() }
        }
        if let modelHost {
            Task { await modelHost.unload() }
        }
        if let contextEngine {
            Task { await contextEngine.stopObservingFrontmostApplication() }
        }
    }

    private func configuredOrchestrator() -> InteractionOrchestrator {
        let preferences = UserPreferenceStore()
        do {
            guard let token = try LMStudioTokenStore().retrieveToken() else {
                throw LanguageModelConfigurationError.unavailable
            }

            let backend = try LMStudioBackend(token: token)
            let host = ModelHost(backend: backend)
            modelHost = host

            Task { @MainActor [weak self] in
                do {
                    try await host.prepare()
                    self?.markModelReady(host)
                } catch {
                    NSLog("LEO local model preparation failed: %{public}@", String(describing: error))
                    self?.markModelUnavailable()
                }
            }
            return InteractionOrchestrator(model: host, accessibilityController: MacosUseAccessibilityController(availability: .system), userPreferences: preferences)
        } catch {
            NSLog("LEO local model configuration failed: %{public}@", String(describing: error))
            markModelUnavailable()
            return InteractionOrchestrator(model: UnavailableLanguageModel(), accessibilityController: MacosUseAccessibilityController(availability: .system), userPreferences: preferences)
        }
    }

    private func markModelReady(_ host: ModelHost) {
        guard modelHost === host else { return }
        AppState.shared.markReady()
    }

    private func markModelUnavailable() {
        AppState.shared.setStatus(.custom("Model unavailable"))
    }
}

extension Notification.Name {
    static let leoShowCommandPalette = Notification.Name("com.varun.leo.showCommandPalette")
}

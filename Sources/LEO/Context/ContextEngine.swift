import Foundation

protocol FrontmostApplicationObservationSource: Sendable {
    func updates() -> AsyncStream<FrontmostApplicationSnapshot?>
}

actor ContextEngine {
    private(set) var liveState: LiveState
    private let observationSource: any FrontmostApplicationObservationSource
    private let browserContextProvider: BrowserContextProvider?
    private var observationTask: Task<Void, Never>?

    init(
        liveState: LiveState = LiveState(),
        observationSource: some FrontmostApplicationObservationSource,
        browserContextProvider: BrowserContextProvider? = nil
    ) {
        self.liveState = liveState
        self.observationSource = observationSource
        self.browserContextProvider = browserContextProvider
    }

    func startObservingFrontmostApplication() {
        guard observationTask == nil else { return }

        observationTask = Task { [observationSource] in
            for await snapshot in observationSource.updates() {
                self.updateFrontmostApplication(snapshot)
                await self.refreshBrowserContext()
            }
        }
    }

    func stopObservingFrontmostApplication() {
        observationTask?.cancel()
        observationTask = nil
    }

    func updateFrontmostApplication(_ snapshot: FrontmostApplicationSnapshot?) {
        liveState.frontmostApplication = snapshot
        if browserContextProvider == nil { liveState.browserContext = nil }
        liveState.updatedAt = .now
    }

    func refreshBrowserContext() async {
        guard let browserContextProvider else {
            liveState.browserContext = nil
            return
        }
        if case .available(let context) = await browserContextProvider.currentContext() {
            liveState.browserContext = context
        } else {
            liveState.browserContext = nil
        }
        liveState.updatedAt = .now
    }
}

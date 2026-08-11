import Darwin
import Foundation

struct ResourceSnapshot: Codable, Sendable, Equatable {
    let residentMemoryBytes: UInt64?
    let residentMemoryUnavailableReason: String?
    let activeRequests: Int
    let capturedAt: Date
}

actor ResourceMonitor {
    private var activeRequests = 0
    private let residentMemoryProvider: @Sendable () -> UInt64?

    init(residentMemoryProvider: @escaping @Sendable () -> UInt64? = ResourceMonitor.currentResidentMemoryBytes) {
        self.residentMemoryProvider = residentMemoryProvider
    }

    func requestStarted() { activeRequests += 1 }
    func requestFinished() { activeRequests = max(0, activeRequests - 1) }

    func snapshot() -> ResourceSnapshot {
        let memory = residentMemoryProvider()
        return ResourceSnapshot(residentMemoryBytes: memory, residentMemoryUnavailableReason: memory == nil ? "resident memory measurement unavailable" : nil, activeRequests: activeRequests, capturedAt: .now)
    }

    private static func currentResidentMemoryBytes() -> UInt64? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return UInt64(usage.ru_maxrss)
    }
}

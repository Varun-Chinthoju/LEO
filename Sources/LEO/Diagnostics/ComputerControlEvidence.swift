import Foundation

enum DiagnosticsBounds {
    static let caseIDCharacters = 64
    static let reasonCharacters = 160
    static let identityCharacters = 96
    static let maxCount = 10_000
    static let maxBytes: UInt64 = 100_000_000
    static let maxMilliseconds = 86_400_000.0
    static let maxRate = 1_000_000.0
}

private extension String {
    func diagnosticsTruncated(to limit: Int) -> String {
        String(prefix(limit))
    }
}

enum PermissionStatus: Codable, Sendable, Equatable {
    case granted
    case denied
    case unavailable(reason: String)

    var reason: String? {
        guard case .unavailable(let reason) = self else { return nil }
        return reason
    }

    init(_ status: PermissionStatus) {
        switch status {
        case .granted: self = .granted
        case .denied: self = .denied
        case .unavailable(let reason): self = .unavailable(reason: reason.diagnosticsTruncated(to: DiagnosticsBounds.reasonCharacters))
        }
    }
}

struct PermissionEvidence: Codable, Sendable, Equatable {
    let accessibility: PermissionStatus
    let inputMonitoring: PermissionStatus
    let screenRecording: PermissionStatus

    init(accessibility: PermissionStatus, inputMonitoring: PermissionStatus, screenRecording: PermissionStatus) {
        self.accessibility = PermissionStatus(accessibility)
        self.inputMonitoring = PermissionStatus(inputMonitoring)
        self.screenRecording = PermissionStatus(screenRecording)
    }
}

struct AXEvidence: Codable, Sendable, Equatable {
    let elementCount: Int
    let payloadBytes: UInt64

    init(elementCount: Int, payloadBytes: UInt64) {
        self.elementCount = min(max(0, elementCount), DiagnosticsBounds.maxCount)
        self.payloadBytes = min(payloadBytes, DiagnosticsBounds.maxBytes)
    }
}

struct TimingEvidence: Codable, Sendable, Equatable {
    let contextMilliseconds: Double?
    let toolMilliseconds: Double?

    init(contextMilliseconds: Double?, toolMilliseconds: Double?) {
        self.contextMilliseconds = Self.bound(contextMilliseconds)
        self.toolMilliseconds = Self.bound(toolMilliseconds)
    }

    private static func bound(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return min(value, DiagnosticsBounds.maxMilliseconds)
    }
}

struct ModelEvidence: Codable, Sendable, Equatable {
    let ttftMilliseconds: Double?
    let tokensPerSecond: Double?

    init(ttftMilliseconds: Double?, tokensPerSecond: Double?) {
        self.ttftMilliseconds = Self.bound(ttftMilliseconds, maximum: DiagnosticsBounds.maxMilliseconds)
        self.tokensPerSecond = Self.bound(tokensPerSecond, maximum: DiagnosticsBounds.maxRate)
    }

    private static func bound(_ value: Double?, maximum: Double) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return min(value, maximum)
    }
}

enum WarmColdState: String, Codable, Sendable { case warm, cold, unknown }

struct RuntimeEvidence: Codable, Sendable, Equatable {
    let state: WarmColdState
    let build: String
    let hardware: String

    init(state: WarmColdState, build: String, hardware: String) {
        self.state = state
        self.build = build.diagnosticsTruncated(to: DiagnosticsBounds.identityCharacters)
        self.hardware = hardware.diagnosticsTruncated(to: DiagnosticsBounds.identityCharacters)
    }
}

struct ResourceEvidence: Codable, Sendable, Equatable {
    let idleRSSBytes: UInt64?
    let peakRSSBytes: UInt64?
    let unavailableReason: String?

    init(idleRSSBytes: UInt64?, peakRSSBytes: UInt64?, unavailableReason: String? = nil) {
        self.idleRSSBytes = idleRSSBytes
        self.peakRSSBytes = peakRSSBytes
        self.unavailableReason = unavailableReason?.diagnosticsTruncated(to: DiagnosticsBounds.reasonCharacters)
    }
}

enum EvidenceFailureLayer: String, Codable, Sendable { case permission, context, tool, model, resource, unknown }

enum EvidenceOutcome: Codable, Sendable, Equatable {
    case success
    case failure(layer: EvidenceFailureLayer, reason: String)

    var failureReason: String? {
        guard case .failure(_, let reason) = self else { return nil }
        return reason
    }

    init(_ outcome: EvidenceOutcome) {
        switch outcome {
        case .success: self = .success
        case .failure(let layer, let reason): self = .failure(layer: layer, reason: reason.diagnosticsTruncated(to: DiagnosticsBounds.reasonCharacters))
        }
    }
}

struct ComputerControlEvidence: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let recordedAt: Date
    let caseID: String
    let permission: PermissionEvidence
    let accessibility: AXEvidence
    let timings: TimingEvidence
    let model: ModelEvidence
    let runtime: RuntimeEvidence
    let memory: ResourceEvidence
    let outcome: EvidenceOutcome

    init(caseID: String, permission: PermissionEvidence, accessibility: AXEvidence, timings: TimingEvidence, model: ModelEvidence, runtime: RuntimeEvidence, memory: ResourceEvidence, outcome: EvidenceOutcome, recordedAt: Date = .now) {
        self.schemaVersion = 1
        self.recordedAt = recordedAt
        self.caseID = caseID.diagnosticsTruncated(to: DiagnosticsBounds.caseIDCharacters)
        self.permission = permission
        self.accessibility = accessibility
        self.timings = timings
        self.model = model
        self.runtime = runtime
        self.memory = memory
        self.outcome = EvidenceOutcome(outcome)
    }

    static func fixture(caseID: String) -> Self {
        Self(caseID: caseID, permission: PermissionEvidence(accessibility: .unavailable(reason: "test"), inputMonitoring: .unavailable(reason: "test"), screenRecording: .unavailable(reason: "test")), accessibility: AXEvidence(elementCount: 0, payloadBytes: 0), timings: TimingEvidence(contextMilliseconds: nil, toolMilliseconds: nil), model: ModelEvidence(ttftMilliseconds: nil, tokensPerSecond: nil), runtime: RuntimeEvidence(state: .unknown, build: "test", hardware: "test"), memory: ResourceEvidence(idleRSSBytes: nil, peakRSSBytes: nil, unavailableReason: "test"), outcome: .success)
    }
}

actor LocalEvidenceStore {
    private let capacity: Int
    private var values: [ComputerControlEvidence] = []

    init(capacity: Int = 256) { self.capacity = max(1, capacity) }

    func append(_ value: ComputerControlEvidence) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    func records() -> [ComputerControlEvidence] { values }
}

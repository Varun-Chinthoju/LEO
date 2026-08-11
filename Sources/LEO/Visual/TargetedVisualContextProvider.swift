import Foundation

enum ScreenRecordingPermissionStatus: Sendable, Equatable, Codable {
    case authorized
    case notGranted
}

protocol ScreenRecordingPermissionProviding: Sendable {
    func status() -> ScreenRecordingPermissionStatus
}

enum TargetedVisualCaptureBounds: Sendable, Equatable, Codable {
    case frontmostWindow(maxPixelDimension: Int)

    var maxPixelDimension: Int {
        switch self {
        case .frontmostWindow(let maxPixelDimension): return maxPixelDimension
        }
    }
}

enum VisualRedactionPolicy: Sendable, Equatable, Codable {
    /// Return no pixels. This is the safe default for callers that only need
    /// a visual-context availability signal or metadata in a future adapter.
    case metadataOnly
    /// Return a downscaled, one-shot image. The capture remains bounded and
    /// does not expose window coordinates or an accessibility tree.
    case pixelsBounded
}

struct TargetedVisualContextRequest: Sendable, Equatable, Codable {
    let reason: String
    let bounds: TargetedVisualCaptureBounds
    let redactionPolicy: VisualRedactionPolicy

    init(
        reason: String,
        bounds: TargetedVisualCaptureBounds = .frontmostWindow(maxPixelDimension: 768),
        redactionPolicy: VisualRedactionPolicy = .metadataOnly
    ) {
        self.reason = reason
        self.bounds = bounds
        self.redactionPolicy = redactionPolicy
    }
}

struct TargetedVisualContextPayload: Sendable, Equatable {
    let imageData: Data?
    let pixelWidth: Int
    let pixelHeight: Int
    let request: TargetedVisualContextRequest
    let permission: ScreenRecordingPermissionStatus

    init(
        imageData: Data? = nil,
        pixelWidth: Int,
        pixelHeight: Int,
        request: TargetedVisualContextRequest,
        permission: ScreenRecordingPermissionStatus = .authorized
    ) {
        self.imageData = imageData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.request = request
        self.permission = permission
    }
}

enum TargetedVisualContextUnavailableReason: Sendable, Equatable {
    case invalidRequest
    case screenRecordingNotGranted(
        reason: String,
        bounds: TargetedVisualCaptureBounds,
        redactionPolicy: VisualRedactionPolicy,
        permission: ScreenRecordingPermissionStatus
    )
    case captureUnavailable
}

enum TargetedVisualContextResult: Sendable, Equatable {
    case available(TargetedVisualContextPayload)
    case unavailable(TargetedVisualContextUnavailableReason)
}

protocol TargetedVisualCapture: Sendable {
    func capture(request: TargetedVisualContextRequest) async -> TargetedVisualContextResult
}

struct TargetedVisualContextProvider: Sendable {
    private let permission: any ScreenRecordingPermissionProviding
    private let captureAdapter: any TargetedVisualCapture

    init(
        permission: some ScreenRecordingPermissionProviding,
        capture: some TargetedVisualCapture
    ) {
        self.permission = permission
        self.captureAdapter = capture
    }

    func capture(request: TargetedVisualContextRequest) async -> TargetedVisualContextResult {
        guard !request.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unavailable(.invalidRequest)
        }

        let permissionStatus = permission.status()
        guard permissionStatus == .authorized else {
            return .unavailable(.screenRecordingNotGranted(
                reason: request.reason,
                bounds: request.bounds,
                redactionPolicy: request.redactionPolicy,
                permission: permissionStatus
            ))
        }

        let result = await captureAdapter.capture(request: request)
        guard case .available(let payload) = result else { return result }
        return .available(TargetedVisualContextPayload(
            imageData: payload.imageData,
            pixelWidth: payload.pixelWidth,
            pixelHeight: payload.pixelHeight,
            request: request,
            permission: permissionStatus
        ))
    }
}

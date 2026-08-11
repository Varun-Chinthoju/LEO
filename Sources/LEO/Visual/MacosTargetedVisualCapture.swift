import AppKit
import CoreGraphics
import Foundation

/// A concrete, one-shot frontmost-window adapter. It deliberately does not
/// expose window coordinates, continuously observe windows, or invoke vision.
struct MacosTargetedVisualCapture: TargetedVisualCapture, Sendable {
    private let maxEncodedBytes = 4 * 1024 * 1024

    func capture(request: TargetedVisualContextRequest) async -> TargetedVisualContextResult {
        guard case .frontmostWindow(let requestedDimension) = request.bounds,
              request.redactionPolicy != .metadataOnly else {
            return .available(TargetedVisualContextPayload(
                pixelWidth: 0,
                pixelHeight: 0,
                request: request
            ))
        }

        let maxDimension = min(max(requestedDimension, 1), 1_024)
        guard let windowID = frontmostWindowID() else {
            return .unavailable(.captureUnavailable)
        }
        guard let image = CGWindowListCreateImage(
            .null,
            .optionOnScreenOnly,
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ), let bounded = boundedImage(image, maxDimension: maxDimension),
              let data = pngData(for: bounded), data.count <= maxEncodedBytes else {
            return .unavailable(.captureUnavailable)
        }

        return .available(TargetedVisualContextPayload(
            imageData: data,
            pixelWidth: bounded.width,
            pixelHeight: bounded.height,
            request: request
        ))
    }

    private func frontmostWindowID() -> CGWindowID? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        return windows?.compactMap { (window: [String: Any]) -> CGWindowID? in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID != ownPID,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let number = window[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return number
        }.first
    }

    private func boundedImage(_ image: CGImage, maxDimension: Int) -> CGImage? {
        guard max(image.width, image.height) > maxDimension else { return image }
        let scale = CGFloat(maxDimension) / CGFloat(max(image.width, image.height))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded(.down)))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded(.down)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func pngData(for image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

struct SystemScreenRecordingPermission: ScreenRecordingPermissionProviding, Sendable {
    func status() -> ScreenRecordingPermissionStatus {
        CGPreflightScreenCaptureAccess() ? .authorized : .notGranted
    }
}

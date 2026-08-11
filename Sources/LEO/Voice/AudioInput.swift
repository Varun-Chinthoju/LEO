import AVFoundation
import Foundation

protocol AudioCaptureBackend: AnyObject {
    func start(onFrame: @escaping (AudioFrame) -> Void) throws
    func stop()
}

enum AudioInputError: Error, Equatable { case alreadyRunning, notRunning, microphoneUnavailable }

final class AudioInput: @unchecked Sendable {
    private let backend: AudioCaptureBackend
    private(set) var isRunning = false
    var onFrame: ((AudioFrame) -> Void)?

    init(backend: AudioCaptureBackend) { self.backend = backend }

    func start() throws {
        guard !isRunning else { throw AudioInputError.alreadyRunning }
        try backend.start { [weak self] frame in self?.onFrame?(frame) }
        isRunning = true
    }

    func stop() {
        backend.stop()
        isRunning = false
    }
}

final class MockAudioCaptureBackend: AudioCaptureBackend {
    private(set) var isRunning = false
    private var onFrame: ((AudioFrame) -> Void)?
    func start(onFrame: @escaping (AudioFrame) -> Void) throws {
        guard !isRunning else { throw AudioInputError.alreadyRunning }
        isRunning = true
        self.onFrame = onFrame
    }
    func stop() { isRunning = false; onFrame = nil }
    func emit(_ frame: AudioFrame) { onFrame?(frame) }
}

final class AVAudioEngineCaptureBackend: AudioCaptureBackend {
    private let engine = AVAudioEngine()
    private var tapInstalled = false

    func start(onFrame: @escaping (AudioFrame) -> Void) throws {
        guard !tapInstalled else { throw AudioInputError.alreadyRunning }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, time in
            guard let data = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength) * Int(buffer.format.channelCount)
            onFrame(AudioFrame(samples: Array(UnsafeBufferPointer(start: data[0], count: count)), sampleRate: buffer.format.sampleRate, channelCount: Int(buffer.format.channelCount), timestamp: Double(time.sampleTime) / buffer.format.sampleRate))
        }
        do {
            try engine.start()
            tapInstalled = true
        } catch {
            input.removeTap(onBus: 0)
            throw AudioInputError.microphoneUnavailable
        }
    }

    func stop() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
    }
}

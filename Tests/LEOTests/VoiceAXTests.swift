import XCTest
@testable import LEO

final class VoiceAXTests: XCTestCase {
    func testMockSpeechRecognizerEmitsPartialThenFinal() async throws {
        let recognizer = MockSpeechRecognizer(transcript: "open Mail")
        var events: [SpeechRecognitionEvent] = []
        for await event in try await recognizer.recognize(frames: []) { events.append(event) }
        XCTAssertEqual(events, [.partial("open Mail"), .final("open Mail")])
    }

    func testParakeetRecognizerUsesConfiguredModelAndEmitsTranscript() async throws {
        let command = RecordingParakeetCommand(transcript: "open Mail")
        let recognizer = ParakeetSpeechRecognizer(model: "test/parakeet", command: command)
        var events: [SpeechRecognitionEvent] = []
        for try await event in try await recognizer.recognize(frames: [AudioFrame(samples: [0.25, -0.25])]) {
            events.append(event)
        }

        XCTAssertEqual(events, [.final("open Mail")])
        XCTAssertEqual(command.models, ["test/parakeet"])
        XCTAssertEqual(command.audioHeaders.first, Data("RIFF".utf8))
    }

    func testParakeetRecognizerRejectsEmptyAudio() async {
        let recognizer = ParakeetSpeechRecognizer(command: RecordingParakeetCommand(transcript: "unused"))
        do {
            _ = try await recognizer.recognize(frames: [])
            XCTFail("Expected empty audio to fail")
        } catch let error as ParakeetSpeechRecognizerError {
            XCTAssertEqual(error, .noAudio)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSpeechEndpointRequiresSpeechThenEndsAfterSustainedSilence() {
        var detector = SpeechEndpointDetector(energyThreshold: 0.1, requiredSilence: 0.5)
        let speech = AudioFrame(samples: Array(repeating: Float(0.4), count: 1_600), sampleRate: 16_000)
        let shortSilence = AudioFrame(samples: Array(repeating: Float(0), count: 4_800), sampleRate: 16_000)
        let finalSilence = AudioFrame(samples: Array(repeating: Float(0), count: 4_000), sampleRate: 16_000)

        XCTAssertEqual(detector.observe(shortSilence), .silence)
        XCTAssertEqual(detector.observe(speech), .speechStarted)
        XCTAssertEqual(detector.observe(shortSilence), .speechContinued)
        XCTAssertEqual(detector.observe(finalSilence), .speechEnded)
        XCTAssertTrue(detector.hasSpeech)
    }

    func testSpeechEndpointDefaultAllowsAPauseButEndsPromptly() {
        var detector = SpeechEndpointDetector(energyThreshold: 0.1)
        let speech = AudioFrame(samples: Array(repeating: Float(0.4), count: 1_600), sampleRate: 16_000)
        let oneSecondSilence = AudioFrame(samples: Array(repeating: Float(0), count: 16_000), sampleRate: 16_000)

        XCTAssertEqual(detector.observe(speech), .speechStarted)
        XCTAssertEqual(detector.observe(oneSecondSilence), .speechContinued)
        XCTAssertEqual(detector.observe(oneSecondSilence), .speechEnded)
    }

    func testSpeechEndpointDefaultRecognizesQuietMicrophoneSpeech() {
        var detector = SpeechEndpointDetector()
        let quietSpeech = AudioFrame(samples: Array(repeating: Float(0.01), count: 1_600), sampleRate: 16_000)

        XCTAssertEqual(detector.observe(quietSpeech), .speechStarted)
        XCTAssertTrue(detector.hasSpeech)
    }

    func testSpeakerEnrollmentStoresEmbeddingButCanReset() throws {
        var enrollment = SpeakerEnrollment()
        let profile = try enrollment.enroll(embeddings: [[1, 2], [3, 4]])
        XCTAssertEqual(profile.embedding, [2, 3])
        enrollment.reset()
        XCTAssertNil(enrollment.profile)
    }

    func testAXCompressionDropsNoiseAndBoundsOutput() {
        let compressor = AXStateCompressor(maxElements: 1)
        let elements = [
            AXRawElement(role: "group", label: nil, value: nil, actions: [], isVisible: true, isStructural: true),
            AXRawElement(role: "button", label: "Save", value: nil, actions: ["press"], isVisible: true, isStructural: false),
            AXRawElement(role: "text", label: "Hidden", value: nil, actions: [], isVisible: false, isStructural: false)
        ]
        XCTAssertEqual(compressor.compress(elements), [AXCompressedElement(role: "button", label: "Save", value: nil, actions: ["press"])])
    }

    func testAXCompressionRedactsSecureValuesAndDropsUnsupportedActions() {
        let compressor = AXStateCompressor(maxElements: 2)
        let output = compressor.compress([
            AXRawElement(role: "secureTextField", label: String(repeating: "x", count: 200), value: "secret", actions: ["press", "delete", "cancel"], isVisible: true, isStructural: false)
        ])
        XCTAssertEqual(output.first?.value, "[redacted]")
        XCTAssertEqual(output.first?.actions, ["press", "cancel"])
        XCTAssertEqual(output.first?.label?.count, 121)
    }
}

private final class RecordingParakeetCommand: ParakeetTranscriptionCommand, @unchecked Sendable {
    let transcript: String
    private(set) var models: [String] = []
    private(set) var audioHeaders: [Data] = []

    init(transcript: String) { self.transcript = transcript }

    func transcribe(audioURL: URL, model: String) throws -> String {
        models.append(model)
        audioHeaders.append(Data(try Data(contentsOf: audioURL).prefix(4)))
        return transcript
    }
}

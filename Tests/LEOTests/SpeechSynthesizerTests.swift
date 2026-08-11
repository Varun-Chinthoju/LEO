import XCTest
@testable import LEO

final class SpeechSynthesizerTests: XCTestCase {
    func testDefaultVoiceUsesQwenMaleVoice() {
        let configuration = KokoroSpeechConfiguration()

        XCTAssertEqual(configuration.model, "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit")
        XCTAssertEqual(configuration.voice, "Ryan")
        XCTAssertEqual(configuration.languageCode, "English")
    }

    func testVoiceClientSpeaksResponseThroughSharedCore() async {
        let synthesizer = MockSpeechSynthesizer()
        let client = VoiceClient(orchestrator: InteractionOrchestrator(), synthesizer: synthesizer)
        _ = await client.submit(transcript: "hello")
        let spoken = await synthesizer.spokenTexts()
        XCTAssertEqual(spoken, ["Done."])
    }

    func testVoiceClientCanStopSpeakingImmediately() async {
        let synthesizer = MockSpeechSynthesizer()
        let client = VoiceClient(orchestrator: InteractionOrchestrator(), synthesizer: synthesizer)

        await client.stopSpeaking()

        let stopCount = await synthesizer.stopCount
        XCTAssertEqual(stopCount, 1)
    }

    func testTypedAndCLIPresentationDefaultsAreSilent() {
        XCTAssertFalse(PresentationPreference.commandPalette.speakResponse)
        XCTAssertFalse(PresentationPreference.cli.speakResponse)
        XCTAssertTrue(PresentationPreference.voice.speakResponse)
    }
}

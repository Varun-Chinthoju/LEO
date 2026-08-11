import XCTest
@testable import LEO

final class AudioLevelMeterTests: XCTestCase {
    func testSilentFrameHasNoLevel() {
        XCTAssertEqual(AudioLevelMeter.level(for: AudioFrame(samples: [0, 0, 0])), 0)
    }

    func testLevelUsesRMSAndClampsToUnitRange() {
        let level = AudioLevelMeter.level(for: AudioFrame(samples: [0.25, -0.25]))
        XCTAssertEqual(level, 1, accuracy: 0.0001)

        let quieterLevel = AudioLevelMeter.level(for: AudioFrame(samples: [0.1, -0.1]))
        XCTAssertEqual(quieterLevel, 1.0, accuracy: 0.0001)
    }
}

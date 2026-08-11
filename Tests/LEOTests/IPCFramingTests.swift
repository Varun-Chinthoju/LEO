import Foundation
import XCTest
@testable import LEO

final class IPCFramingTests: XCTestCase {
    func testPartialFramesReassembleAndStreamMultipleMessages() throws {
        let first = try IPCFraming.encode(IPCMessage(payload: .event(.thinking)))
        let second = try IPCFraming.encode(IPCMessage(payload: .event(.responseCompleted("done"))))
        var decoder = IPCFraming()
        XCTAssertTrue(try decoder.append(first.prefix(3)).isEmpty)
        XCTAssertEqual(try decoder.append(first.dropFirst(3) + second).count, 2)
    }

    func testMalformedAndUnsupportedFramesAreRejected() throws {
        var decoder = IPCFraming()
        XCTAssertThrowsError(try decoder.append(Data([0, 0, 0, 2, 1, 2])))
        let payload = try JSONEncoder().encode(IPCMessage(version: 99, payload: .event(.thinking)))
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        XCTAssertThrowsError(try decoder.append(frame)) { XCTAssertEqual($0 as? IPCFramingError, .unsupportedVersion(99)) }
    }
}

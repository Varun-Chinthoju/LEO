import Foundation
import XCTest
@testable import LEO

final class CoreContractsTests: XCTestCase {
    func testRequestSourceDefaultsDrivePresentationPreferences() {
        XCTAssertEqual(PresentationPreference.defaultPresentation(for: .voice), .voice)
        XCTAssertEqual(PresentationPreference.defaultPresentation(for: .commandPalette), .commandPalette)
        XCTAssertEqual(PresentationPreference.defaultPresentation(for: .cli), .cli)

        XCTAssertTrue(PresentationPreference.voice.speakResponse)
        XCTAssertFalse(PresentationPreference.commandPalette.speakResponse)
        XCTAssertFalse(PresentationPreference.cli.speakResponse)
    }

    func testAssistantRequestDefaultsPresentationFromSource() {
        let voiceRequest = AssistantRequest(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            sessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            input: .text("Open Mail"),
            source: .voice,
            createdAt: Date(timeIntervalSinceReferenceDate: 1234)
        )

        let cliRequest = AssistantRequest(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            sessionID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            input: .text("List files"),
            source: .cli,
            createdAt: Date(timeIntervalSinceReferenceDate: 5678)
        )

        XCTAssertEqual(voiceRequest.presentation, .voice)
        XCTAssertEqual(cliRequest.presentation, .cli)
    }

    func testAssistantRequestRoundTripsThroughCodable() throws {
        let request = AssistantRequest(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            sessionID: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            input: .text("Summarize the latest note"),
            source: .commandPalette,
            createdAt: Date(timeIntervalSinceReferenceDate: 9012),
            presentation: .commandPalette
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(AssistantRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    func testAssistantEventCasesRoundTripThroughCodable() throws {
        let actionID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let confirmationID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!

        let events: [AssistantEvent] = [
            .accepted(UUID(uuidString: "99999999-9999-9999-9999-999999999999")!),
            .thinking,
            .reasoningSummary("Checking the requested file"),
            .actionStarted(ActionSummary(id: actionID, title: "Open app", detail: "Launch Mail")),
            .actionProgress(ActionProgress(actionID: actionID, detail: "Waiting for launch", fractionCompleted: 0.5)),
            .actionFinished(ActionResultSummary(actionID: actionID, title: "Open app", detail: "Mail is active", succeeded: true)),
            .responseDelta("Done"),
            .responseCompleted("Done"),
            .confirmationRequired(ConfirmationRequest(id: confirmationID, title: "Delete file?", detail: "This cannot be undone", defaultIsConfirmed: false)),
            .failed(AssistantFailure(message: "Permission denied", code: "permissionDenied", isRecoverable: false))
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for event in events {
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(AssistantEvent.self, from: data)

            XCTAssertEqual(decoded, event)
        }
    }
}

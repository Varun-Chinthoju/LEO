import XCTest
@testable import LEO

final class HotkeyManagerTests: XCTestCase {
    func testDefaultConfigurationUsesSeparateStableIdentifiersAndShortcuts() {
        let configuration = HotkeyConfiguration.default

        XCTAssertEqual(configuration.typedCommandPalette.shortcut, HotkeyShortcut(keyCode: 49, modifiers: [.option, .shift]))
        XCTAssertEqual(configuration.voicePushToTalk.shortcut, HotkeyShortcut(keyCode: 49, modifiers: [.option]))
        XCTAssertEqual(configuration.typedCommandPalette.role.identifier.rawValue, "typedCommandPalette")
        XCTAssertEqual(configuration.voicePushToTalk.role.identifier.rawValue, "voicePushToTalk")
    }

    func testStartRegistersBothHotkeysAndStopUnregistersThem() throws {
        let backend = FakeHotkeyBackend()
        let manager = HotkeyManager(backend: backend)

        try manager.start()

        XCTAssertEqual(backend.registeredBindings.map(\.role), [.typedCommandPalette, .voicePushToTalk])
        XCTAssertEqual(backend.registeredBindings.map(\.shortcut), [HotkeyShortcut(keyCode: 49, modifiers: [.option, .shift]), HotkeyShortcut(keyCode: 49, modifiers: [.option])])

        manager.stop()

        XCTAssertEqual(backend.unregisteredIdentifiers.map(\.rawValue), ["typedCommandPalette", "voicePushToTalk"])
    }

    func testTypedShortcutEmitsOnceForKeyDownAndIgnoresKeyUp() throws {
        let backend = FakeHotkeyBackend()
        let manager = HotkeyManager(backend: backend)
        var events: [HotkeyEvent] = []
        manager.onEvent = { events.append($0) }

        try manager.start()

        backend.emit(.init(role: .typedCommandPalette, phase: .down))
        backend.emit(.init(role: .typedCommandPalette, phase: .up))

        XCTAssertEqual(events, [.typedCommandPaletteRequested])
    }

    func testRepeatedKeyDownDoesNotToggleVoiceCaptureAgain() throws {
        let backend = FakeHotkeyBackend()
        let manager = HotkeyManager(backend: backend)
        var events: [HotkeyEvent] = []
        manager.onEvent = { events.append($0) }

        try manager.start()

        backend.emit(.init(role: .voicePushToTalk, phase: .down))
        backend.emit(.init(role: .voicePushToTalk, phase: .down))
        backend.emit(.init(role: .voicePushToTalk, phase: .up))
        backend.emit(.init(role: .voicePushToTalk, phase: .down))

        XCTAssertEqual(events, [.voicePushToTalkBegan, .voicePushToTalkEnded, .voicePushToTalkBegan])
    }

    func testVoiceShortcutEmitsSeparateBeganAndEndedEvents() throws {
        let backend = FakeHotkeyBackend()
        let manager = HotkeyManager(backend: backend)
        var events: [HotkeyEvent] = []
        manager.onEvent = { events.append($0) }

        try manager.start()

        backend.emit(.init(role: .voicePushToTalk, phase: .down))
        backend.emit(.init(role: .voicePushToTalk, phase: .up))

        XCTAssertEqual(events, [.voicePushToTalkBegan, .voicePushToTalkEnded])
    }

    func testUpdatingConfigurationUnregistersOldBindingsAndRegistersNewOnes() throws {
        let backend = FakeHotkeyBackend()
        let manager = HotkeyManager(backend: backend)

        try manager.start()

        let updatedConfiguration = HotkeyConfiguration(
            typedCommandPalette: HotkeyBinding(role: .typedCommandPalette, shortcut: HotkeyShortcut(keyCode: 18, modifiers: [.command])),
            voicePushToTalk: HotkeyBinding(role: .voicePushToTalk, shortcut: HotkeyShortcut(keyCode: 19, modifiers: [.command]))
        )

        try manager.updateConfiguration(updatedConfiguration)

        XCTAssertEqual(backend.unregisteredIdentifiers.map(\.rawValue), ["typedCommandPalette", "voicePushToTalk"])
        XCTAssertEqual(backend.registeredBindings.map(\.shortcut), [HotkeyShortcut(keyCode: 18, modifiers: [.command]), HotkeyShortcut(keyCode: 19, modifiers: [.command])])
    }
}

private final class FakeHotkeyBackend: HotkeyBackend {
    private(set) var registeredBindings: [HotkeyBinding] = []
    private(set) var unregisteredIdentifiers: [HotkeyIdentifier] = []
    private var eventHandler: ((HotkeyBackendEvent) -> Void)?

    func setEventHandler(_ handler: ((HotkeyBackendEvent) -> Void)?) {
        eventHandler = handler
    }

    func register(_ binding: HotkeyBinding) throws {
        registeredBindings.removeAll { $0.role == binding.role }
        registeredBindings.append(binding)
    }

    func unregister(_ identifier: HotkeyIdentifier) {
        unregisteredIdentifiers.append(identifier)
        registeredBindings.removeAll { $0.role.identifier == identifier }
    }

    func emit(_ event: HotkeyBackendEvent) {
        eventHandler?(event)
    }
}

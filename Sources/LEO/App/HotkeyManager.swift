import AppKit
import Foundation

struct HotkeyShortcut: Equatable, Sendable {
    struct Modifiers: OptionSet, Equatable, Sendable {
        let rawValue: UInt

        static let command = Self(rawValue: 1 << 0)
        static let option = Self(rawValue: 1 << 1)
        static let control = Self(rawValue: 1 << 2)
        static let shift = Self(rawValue: 1 << 3)
    }

    let keyCode: UInt16
    let modifiers: Modifiers
}

struct HotkeyIdentifier: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

enum HotkeyRole: Equatable, Sendable {
    case typedCommandPalette
    case voicePushToTalk

    var identifier: HotkeyIdentifier {
        switch self {
        case .typedCommandPalette:
            return HotkeyIdentifier(rawValue: "typedCommandPalette")
        case .voicePushToTalk:
            return HotkeyIdentifier(rawValue: "voicePushToTalk")
        }
    }
}

struct HotkeyBinding: Equatable, Sendable {
    let role: HotkeyRole
    let shortcut: HotkeyShortcut
}

struct HotkeyConfiguration: Equatable, Sendable {
    let typedCommandPalette: HotkeyBinding
    let voicePushToTalk: HotkeyBinding

    static let `default` = Self(
        typedCommandPalette: HotkeyBinding(
            role: .typedCommandPalette,
            shortcut: HotkeyShortcut(keyCode: 49, modifiers: [.option, .shift])
        ),
        voicePushToTalk: HotkeyBinding(
            role: .voicePushToTalk,
            shortcut: HotkeyShortcut(keyCode: 49, modifiers: [.option])
        )
    )

    var bindings: [HotkeyBinding] {
        [typedCommandPalette, voicePushToTalk]
    }
}

enum HotkeyPhase: Sendable {
    case down
    case up
}

struct HotkeyBackendEvent: Sendable {
    let role: HotkeyRole
    let phase: HotkeyPhase
}

protocol HotkeyBackend: AnyObject {
    func setEventHandler(_ handler: ((HotkeyBackendEvent) -> Void)?)
    func register(_ binding: HotkeyBinding) throws
    func unregister(_ identifier: HotkeyIdentifier)
}

enum HotkeyEvent: Equatable, Sendable {
    case typedCommandPaletteRequested
    case voicePushToTalkBegan
    case voicePushToTalkEnded
}

final class HotkeyManager {
    private(set) var configuration: HotkeyConfiguration
    private let backend: HotkeyBackend
    private var pressedIdentifiers: Set<HotkeyIdentifier> = []
    private(set) var isStarted = false
    var onEvent: ((HotkeyEvent) -> Void)?

    init(configuration: HotkeyConfiguration = .default, backend: HotkeyBackend) {
        self.configuration = configuration
        self.backend = backend
    }

    func start() throws {
        guard !isStarted else { return }
        backend.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        do {
            for binding in configuration.bindings {
                try backend.register(binding)
            }
            isStarted = true
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        guard isStarted || configuration.bindings.isEmpty == false else { return }
        for binding in configuration.bindings {
            backend.unregister(binding.role.identifier)
        }
        backend.setEventHandler(nil)
        pressedIdentifiers.removeAll()
        isStarted = false
    }

    func updateConfiguration(_ configuration: HotkeyConfiguration) throws {
        let wasStarted = isStarted
        if wasStarted { stop() }
        self.configuration = configuration
        if wasStarted { try start() }
    }

    private func handle(_ event: HotkeyBackendEvent) {
        switch (event.role, event.phase) {
        case (.typedCommandPalette, .down):
            guard pressedIdentifiers.insert(event.role.identifier).inserted else { return }
            onEvent?(.typedCommandPaletteRequested)
        case (.typedCommandPalette, .up):
            pressedIdentifiers.remove(event.role.identifier)
        case (.voicePushToTalk, .down):
            guard pressedIdentifiers.insert(event.role.identifier).inserted else { return }
            onEvent?(.voicePushToTalkBegan)
        case (.voicePushToTalk, .up):
            pressedIdentifiers.remove(event.role.identifier)
            onEvent?(.voicePushToTalkEnded)
        }
    }
}

final class SystemHotkeyBackend: HotkeyBackend {
    private var monitors: [HotkeyIdentifier: [Any]] = [:]
    private var handler: ((HotkeyBackendEvent) -> Void)?

    func setEventHandler(_ handler: ((HotkeyBackendEvent) -> Void)?) {
        self.handler = handler
    }

    func register(_ binding: HotkeyBinding) throws {
        unregister(binding.role.identifier)
        let down = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.matches(event, shortcut: binding.shortcut) else { return }
            self?.handler?(HotkeyBackendEvent(role: binding.role, phase: .down))
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard Self.matches(event, shortcut: binding.shortcut) else { return }
            self?.handler?(HotkeyBackendEvent(role: binding.role, phase: .up))
        }
        // Global monitors do not receive events dispatched to LEO itself. Keep a
        // local monitor as well so the same shortcut works after opening the
        // menu-bar popover or while the palette is already key.
        let localDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.matches(event, shortcut: binding.shortcut) else { return event }
            self?.handler?(HotkeyBackendEvent(role: binding.role, phase: .down))
            return nil
        }
        let localUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard Self.matches(event, shortcut: binding.shortcut) else { return event }
            self?.handler?(HotkeyBackendEvent(role: binding.role, phase: .up))
            return nil
        }
        monitors[binding.role.identifier] = [down as Any, up as Any, localDown as Any, localUp as Any]
    }

    func unregister(_ identifier: HotkeyIdentifier) {
        for monitor in monitors.removeValue(forKey: identifier) ?? [] {
            NSEvent.removeMonitor(monitor)
        }
    }

    private static func matches(_ event: NSEvent, shortcut: HotkeyShortcut) -> Bool {
        guard event.keyCode == shortcut.keyCode else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var expected: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.command) { expected.insert(.command) }
        if shortcut.modifiers.contains(.option) { expected.insert(.option) }
        if shortcut.modifiers.contains(.control) { expected.insert(.control) }
        if shortcut.modifiers.contains(.shift) { expected.insert(.shift) }
        return flags == expected
    }
}

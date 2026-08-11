import AppKit
import ApplicationServices
import Foundation

actor MacosUseAccessibilityController: AccessibilityController {
    enum Availability: Sendable { case unavailable, available, system }

    private let availability: Availability
    private let compressor: AXStateCompressor
    private let maxDepth = 6
    private let maxNodes = 250

    init(availability: Availability = .unavailable, compressor: AXStateCompressor = AXStateCompressor()) {
        self.availability = availability
        self.compressor = compressor
    }

    func snapshotFrontmostApplication() async throws -> AXSnapshot {
        let application = try frontmostApplication()
        let root = AXUIElementCreateApplication(application.processIdentifier)
        let raw = collect(from: root, path: "", depth: 0, remaining: maxNodes)
        return AXSnapshot(
            applicationName: application.localizedName,
            bundleIdentifier: application.bundleIdentifier,
            elements: compressor.compress(raw.elements.map(\.raw))
        )
    }

    func find(_ query: AXQuery) async throws -> [AXElementReference] {
        guard !query.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AccessibilityControllerError.invalidQuery
        }
        let application = try frontmostApplication()
        let root = AXUIElementCreateApplication(application.processIdentifier)
        let raw = collect(from: root, path: "", depth: 0, remaining: maxNodes).matches(query.value)
        return Array(raw.prefix(20)).map {
            let compressed = compressor.compress([$0.raw]).first
            return AXElementReference(identifier: $0.identifier, role: compressed?.role, label: compressed?.label, value: compressed?.value, actions: compressed?.actions ?? [])
        }
    }

    func perform(_ action: AXAction, on element: AXElementReference) async throws {
        guard Self.allowedActions.contains(action.value) else {
            throw AccessibilityControllerError.actionNotAllowed(action.value)
        }
        let application = try frontmostApplication()
        let root = AXUIElementCreateApplication(application.processIdentifier)
        guard let target = elementAtPath(element.identifier, from: root) else {
            throw AccessibilityControllerError.elementUnavailable
        }
        let result = AXUIElementPerformAction(target, Self.axActionName(for: action.value) as CFString)
        guard result == .success else {
            throw AccessibilityControllerError.elementUnavailable
        }
    }

    static let allowedActions: Set<String> = ["press", "increment", "decrement", "confirm", "cancel"]

    private static func axActionName(for action: String) -> String {
        switch action {
        case "press", "confirm": return kAXPressAction
        case "increment": return kAXIncrementAction
        case "decrement": return kAXDecrementAction
        case "cancel": return "AXCancel"
        default: return action
        }
    }

    private func frontmostApplication() throws -> NSRunningApplication {
        switch availability {
        case .unavailable: throw AccessibilityControllerError.unsupported
        case .available: break
        case .system:
            guard AXIsProcessTrusted() else { throw AccessibilityControllerError.permissionDenied }
        }
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw AccessibilityControllerError.elementUnavailable
        }
        return application
    }

    private struct CollectedElement {
        let identifier: String
        let raw: AXRawElement
        let element: AXUIElement
    }

    private struct Collection {
        let elements: [CollectedElement]

        func matches(_ query: String) -> [CollectedElement] {
            let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return elements.filter { item in
                [item.raw.role, item.raw.label, item.raw.value].compactMap { $0 }.contains {
                    $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle)
                }
            }
        }
    }

    private func collect(from element: AXUIElement, path: String, depth: Int, remaining: Int) -> Collection {
        guard depth <= maxDepth, remaining > 0 else { return Collection(elements: []) }
        let role = stringAttribute(kAXRoleAttribute, from: element)
        let label = stringAttribute(kAXTitleAttribute, from: element) ?? stringAttribute(kAXDescriptionAttribute, from: element)
        let value = stringAttribute(kAXValueAttribute, from: element)
        let actions = actionNames(for: element)
        var items = [CollectedElement(identifier: path.isEmpty ? "root" : path, raw: AXRawElement(
            role: role, label: label, value: value, actions: actions, isVisible: true, isStructural: role == "AXGroup" || role == "AXScrollArea" || role == "AXWindow"), element: element)]
        guard depth < maxDepth, let children = children(of: element) else { return Collection(elements: items) }
        for (index, child) in children.prefix(max(0, remaining - items.count)).enumerated() {
            let childPath = path.isEmpty ? "\(index)" : "\(path).\(index)"
            items.append(contentsOf: collect(from: child, path: childPath, depth: depth + 1, remaining: remaining - items.count).elements)
            if items.count >= remaining { break }
        }
        return Collection(elements: Array(items.prefix(remaining)))
    }

    private func elementAtPath(_ path: String, from root: AXUIElement) -> AXUIElement? {
        guard path != "root" else { return root }
        var current = root
        for component in path.split(separator: ".") {
            guard let index = Int(component), let children = children(of: current), index < children.count else { return nil }
            current = children[index]
        }
        return current
    }

    private func children(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return nil }
        return children
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func actionNames(for element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success,
              let names = value as? [String] else { return [] }
        return names.compactMap { name in
            switch name {
            case kAXPressAction: return "press"
            case kAXIncrementAction: return "increment"
            case kAXDecrementAction: return "decrement"
            case "AXCancel": return "cancel"
            default: return nil
            }
        }
    }
}

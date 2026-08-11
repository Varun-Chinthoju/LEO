import Foundation

struct AXSnapshot: Sendable, Equatable, Codable {
    var applicationName: String?
    var bundleIdentifier: String?
    var elements: [AXCompressedElement]

    init(applicationName: String? = nil, bundleIdentifier: String? = nil, elements: [AXCompressedElement] = []) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.elements = elements
    }
}

struct AXQuery: Sendable, Equatable {
    var value: String
}

struct AXElementReference: Sendable, Equatable, Codable {
    var identifier: String
    var role: String?
    var label: String?
    var value: String?
    var actions: [String]

    init(identifier: String, role: String? = nil, label: String? = nil, value: String? = nil, actions: [String] = []) {
        self.identifier = identifier
        self.role = role
        self.label = label
        self.value = value
        self.actions = actions
    }
}

struct AXAction: Sendable, Equatable {
    var value: String
}

enum AccessibilityControllerError: Error, Equatable {
    case permissionDenied
    case unsupported
    case invalidQuery
    case ambiguousMatch
    case actionNotAllowed(String)
    case elementUnavailable
}

extension AccessibilityControllerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Accessibility permission is not enabled for LEO."
        case .unsupported: return "Accessibility is unavailable on this system."
        case .invalidQuery: return "The accessibility query is invalid."
        case .ambiguousMatch: return "The query matched more than one element."
        case .actionNotAllowed(let action): return "Accessibility action is not allowed: \(action)."
        case .elementUnavailable: return "The accessibility element is no longer available."
        }
    }
}

protocol AccessibilityController: Actor {
    func snapshotFrontmostApplication() async throws -> AXSnapshot

    func find(_ query: AXQuery) async throws -> [AXElementReference]

    func perform(_ action: AXAction, on element: AXElementReference) async throws
}

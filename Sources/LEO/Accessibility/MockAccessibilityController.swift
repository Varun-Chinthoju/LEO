import Foundation

actor MockAccessibilityController: AccessibilityController {
    var snapshotResult = AXSnapshot(applicationName: "MockApp")
    var findResult: [AXElementReference] = []
    var performCount = 0
    var denied = false
    var lastQuery: AXQuery?
    var lastAction: AXAction?

    func setDenied(_ denied: Bool) {
        self.denied = denied
    }

    func setFindResult(_ result: [AXElementReference]) {
        self.findResult = result
    }

    func snapshotFrontmostApplication() async throws -> AXSnapshot {
        try validateAccess()
        return snapshotResult
    }

    func find(_ query: AXQuery) async throws -> [AXElementReference] {
        try validateAccess()
        lastQuery = query
        return findResult
    }

    func perform(_ action: AXAction, on element: AXElementReference) async throws {
        try validateAccess()
        lastAction = action
        performCount += 1
    }

    private func validateAccess() throws {
        if denied {
            throw AccessibilityControllerError.permissionDenied
        }
    }
}

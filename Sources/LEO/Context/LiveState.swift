import Foundation

struct FrontmostApplicationSnapshot: Codable, Sendable, Equatable {
    var bundleIdentifier: String?
    var localizedName: String?
    var processIdentifier: Int32?
}

struct LiveState: Codable, Sendable, Equatable {
    var frontmostApplication: FrontmostApplicationSnapshot?
    var browserContext: BrowserContext?
    var updatedAt: Date

    init(
        frontmostApplication: FrontmostApplicationSnapshot? = nil,
        browserContext: BrowserContext? = nil,
        updatedAt: Date = .now
    ) {
        self.frontmostApplication = frontmostApplication
        self.browserContext = browserContext
        self.updatedAt = updatedAt
    }
}

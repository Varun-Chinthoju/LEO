import AppKit
import Foundation

struct InstalledApplication: Sendable, Equatable {
    let name: String
    let bundleIdentifier: String?
    let url: URL
}

protocol AppProvider: Sendable {
    func findApplication(named name: String) -> InstalledApplication?
    func open(_ application: InstalledApplication) -> Bool
}

struct WorkspaceAppProvider: AppProvider {
    func findApplication(named name: String) -> InstalledApplication? {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(toOpen: URL(fileURLWithPath: "/Applications/\(name).app"))
            ?? workspace.urlForApplication(toOpen: URL(fileURLWithPath: "/System/Applications/\(name).app")) else { return nil }
        return InstalledApplication(name: name, bundleIdentifier: Bundle(url: url)?.bundleIdentifier, url: url)
    }

    func open(_ application: InstalledApplication) -> Bool {
        let completion = DispatchSemaphore(value: 0)
        let result = LockedOpenResult()
        NSWorkspace.shared.openApplication(at: application.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            result.succeeded = error == nil
            completion.signal()
        }
        completion.wait()
        return result.succeeded
    }
}

struct AppTools {
    let provider: any AppProvider

    init(provider: some AppProvider = WorkspaceAppProvider()) { self.provider = provider }

    func open(name: String) throws -> String {
        guard let application = provider.findApplication(named: name) else {
            throw AppToolError.notInstalled(name)
        }
        guard provider.open(application) else { throw AppToolError.openFailed(name) }
        return "Opened \(application.name)."
    }

    func definition() -> ToolDefinition {
        ToolDefinition(name: "apps.open", effect: .readOnly, idempotency: .idempotent, requiredArguments: ["name"]) { arguments in
            let name = arguments["name"] ?? ""
            return try ToolResult.success(self.open(name: name))
        }
    }
}

enum AppToolError: Error, Equatable {
    case notInstalled(String)
    case openFailed(String)
}

private final class LockedOpenResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var succeeded: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

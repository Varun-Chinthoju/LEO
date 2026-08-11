import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct BrowserContext: Codable, Sendable, Equatable {
    let application: String
    let title: String?
    let url: URL?
}

enum BrowserContextUnavailableReason: Sendable, Equatable {
    case unsupportedBrowser
    case metadataUnavailable
}

enum BrowserContextResult: Sendable, Equatable {
    case available(BrowserContext)
    case unavailable(BrowserContextUnavailableReason)
}

protocol BrowserContextSource: Sendable {
    func currentContext() async throws -> BrowserContext?
}

struct BrowserContextProvider: Sendable {
    private let source: any BrowserContextSource

    init(source: some BrowserContextSource) {
        self.source = source
    }

    /// Returns only the current browser's app name, page title, and URL.
    /// The provider never propagates adapter errors or invents partial context.
    func currentContext() async -> BrowserContextResult {
        do {
            guard let context = try await source.currentContext() else {
                return .unavailable(.unsupportedBrowser)
            }
            return .available(context)
        } catch {
            return .unavailable(.metadataUnavailable)
        }
    }
}

struct MacOSBrowserContextSource: BrowserContextSource {
    private let workspace: WorkspaceProviding
    private let metadataReader: BrowserMetadataReading

    init(
        workspace: WorkspaceProviding = SystemWorkspace(),
        metadataReader: BrowserMetadataReading = AppleScriptBrowserMetadataReader()
    ) {
        self.workspace = workspace
        self.metadataReader = metadataReader
    }

    func currentContext() async throws -> BrowserContext? {
        guard let application = workspace.frontmostApplication,
              let browser = SupportedBrowser(bundleIdentifier: application.bundleIdentifier)
        else {
            return nil
        }

        let metadata = try await metadataReader.readMetadata(for: browser)
        return BrowserContext(
            application: application.localizedName ?? browser.displayName,
            title: metadata.title,
            url: metadata.url
        )
    }
}

struct BrowserMetadata: Sendable, Equatable {
    let title: String?
    let url: URL?
}

protocol BrowserMetadataReading: Sendable {
    func readMetadata(for browser: SupportedBrowser) async throws -> BrowserMetadata
}

enum SupportedBrowser: Sendable, Equatable {
    case safari
    case chrome
    case brave
    case arc

    init?(bundleIdentifier: String?) {
        switch bundleIdentifier {
        case "com.apple.Safari": self = .safari
        case "com.google.Chrome": self = .chrome
        case "com.brave.Browser": self = .brave
        case "company.thebrowser.Browser": self = .arc
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .brave: return "Brave Browser"
        case .arc: return "Arc"
        }
    }

    var scriptingApplicationName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .brave: return "Brave Browser"
        case .arc: return "Arc"
        }
    }
}

struct WorkspaceApplication: Sendable, Equatable {
    let bundleIdentifier: String?
    let localizedName: String?
}

protocol WorkspaceProviding: Sendable {
    var frontmostApplication: WorkspaceApplication? { get }
}

struct SystemWorkspace: WorkspaceProviding {
    var frontmostApplication: WorkspaceApplication? {
        #if canImport(AppKit)
        let application = NSWorkspace.shared.frontmostApplication
        return application.map {
            WorkspaceApplication(bundleIdentifier: $0.bundleIdentifier, localizedName: $0.localizedName)
        }
        #else
        nil
        #endif
    }
}

struct AppleScriptBrowserMetadataReader: BrowserMetadataReading {
    func readMetadata(for browser: SupportedBrowser) async throws -> BrowserMetadata {
        let script = """
        tell application \"(browser.scriptingApplicationName)\"
            tell front window
                set leoTitle to name
                set leoURL to URL of active tab
            end tell
        end tell
        return leoTitle & character id 31 & leoURL
        """

        let output = try await runAppleScript(script)
        let fields = output.components(separatedBy: String(UnicodeScalar(31)))
        guard fields.count == 2 else { throw BrowserMetadataError.invalidResponse }

        let title = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let rawURL = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return BrowserMetadata(title: title.isEmpty ? nil : title, url: URL(string: rawURL))
    }

    private func runAppleScript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { process in
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: BrowserMetadataError.scriptFailed)
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private enum BrowserMetadataError: Error {
    case invalidResponse
    case scriptFailed
}

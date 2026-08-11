import Foundation

/// A user-created Shortcut that can be selected without exposing UI mechanics.
struct Shortcut: Sendable, Equatable, Codable {
    let name: String
}

struct ShortcutRunResult: Sendable, Equatable {
    let output: String
}

protocol ShortcutsListProvider: Sendable {
    func list() throws -> [Shortcut]
}

protocol ShortcutsExecutor: Sendable {
    func run(shortcut: Shortcut, input: String?) throws -> ShortcutRunResult
}

enum ShortcutsError: Error, Equatable, Sendable {
    case missingShortcut(String)
}

/// Typed Shortcuts integration boundary. OS-specific discovery/execution stays
/// behind the two protocols so this layer cannot fall back to shell commands or
/// coordinate-based UI automation.
struct ShortcutsIntegration: Sendable {
    let listProvider: any ShortcutsListProvider
    let executor: any ShortcutsExecutor

    init(listProvider: some ShortcutsListProvider, executor: some ShortcutsExecutor) {
        self.listProvider = listProvider
        self.executor = executor
    }

    func list() throws -> [Shortcut] {
        try listProvider.list()
    }

    func run(named name: String, input: String? = nil) throws -> String {
        guard let shortcut = try list().first(where: { $0.name == name }) else {
            throw ShortcutsError.missingShortcut(name)
        }
        return try executor.run(shortcut: shortcut, input: input).output
    }

    var toolDefinitions: [ToolDefinition] {
        [
            ToolDefinition(
                name: "shortcuts.list",
                effect: .readOnly,
                idempotency: .idempotent
            ) { _ in
                let names = try self.list().map(\.name)
                return ToolResult.success(names.joined(separator: "\n"))
            },
            ToolDefinition(
                name: "shortcuts.run",
                effect: .consequential,
                idempotency: .nonIdempotent,
                requiredArguments: ["name"]
            ) { arguments in
                try ToolResult.success(self.run(named: arguments["name"] ?? "", input: arguments["input"]))
            }
        ]
    }
}

/// Production adapter for the system `shortcuts` command-line interface.
/// It invokes the fixed executable directly (never through a shell) and keeps
/// the integration typed at the LEO boundary.
struct SystemShortcutsListProvider: ShortcutsListProvider {
    func list() throws -> [Shortcut] {
        let output = try run(arguments: ["list"])
        return output
            .split(whereSeparator: \.isNewline)
            .map { Shortcut(name: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.name.isEmpty }
    }

    fileprivate func run(arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ShortcutsError.missingShortcut(arguments.last ?? "") }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

struct SystemShortcutsExecutor: ShortcutsExecutor {
    private let listProvider = SystemShortcutsListProvider()

    func run(shortcut: Shortcut, input: String?) throws -> ShortcutRunResult {
        var arguments = ["run", shortcut.name]
        if let input, !input.isEmpty {
            arguments += ["--input", input]
        }
        return ShortcutRunResult(output: try listProvider.run(arguments: arguments).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

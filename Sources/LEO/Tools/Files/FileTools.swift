import AppKit
import Foundation

struct FileInspection: Sendable, Equatable {
    let url: URL
    let isDirectory: Bool
    let byteSize: Int64
}

enum FileToolError: Error, Equatable {
    case missing(URL)
    case destinationExists(URL)
    case operationFailed(String)
}

protocol FileSystemProvider: Sendable {
    func inspect(_ url: URL) throws -> FileInspection
    func move(_ source: URL, to destination: URL) throws
    func rename(_ source: URL, to name: String) throws -> URL
    func open(_ url: URL) -> Bool
    func reveal(_ url: URL) -> Bool
}

struct LocalFileSystemProvider: FileSystemProvider {
    func inspect(_ url: URL) throws -> FileInspection {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        guard values.isDirectory != nil || FileManager.default.fileExists(atPath: url.path) else { throw FileToolError.missing(url) }
        return FileInspection(url: url, isDirectory: values.isDirectory ?? false, byteSize: Int64(values.fileSize ?? 0))
    }

    func move(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { throw FileToolError.missing(source) }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw FileToolError.destinationExists(destination) }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func rename(_ source: URL, to name: String) throws -> URL {
        let destination = source.deletingLastPathComponent().appendingPathComponent(name)
        try move(source, to: destination)
        return destination
    }

    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) -> Bool {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }
}

struct FileTools {
    let provider: any FileSystemProvider

    init(provider: some FileSystemProvider = LocalFileSystemProvider()) { self.provider = provider }
    func inspect(_ url: URL) throws -> FileInspection { try provider.inspect(url) }
    func move(_ source: URL, to destination: URL) throws { try provider.move(source, to: destination) }
    func rename(_ source: URL, to name: String) throws -> URL { try provider.rename(source, to: name) }
    @discardableResult func open(_ url: URL) -> Bool { provider.open(url) }
    @discardableResult func reveal(_ url: URL) -> Bool { provider.reveal(url) }
}

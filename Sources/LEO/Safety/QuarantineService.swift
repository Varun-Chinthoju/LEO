import Foundation

struct QuarantineRecord: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let originalURL: URL
    let quarantinedURL: URL
    let requestID: UUID
    let entityID: String?
    let source: RequestSource
    let createdAt: Date
}

enum QuarantineError: Error, Equatable {
    case missing(URL)
    case destinationExists(URL)
    case recordNotFound(UUID)
}

struct QuarantineService: Sendable {
    let rootURL: URL

    init(rootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LEO/Quarantine")) {
        self.rootURL = rootURL
    }

    func quarantine(
        _ url: URL,
        requestID: UUID,
        entityID: String? = nil,
        source: RequestSource = .commandPalette
    ) throws -> QuarantineRecord {
        guard FileManager.default.fileExists(atPath: url.path) else { throw QuarantineError.missing(url) }
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let id = UUID()
        let destination = rootURL.appendingPathComponent("\(id.uuidString)-\(url.lastPathComponent)")
        try FileManager.default.moveItem(at: url, to: destination)
        let record = QuarantineRecord(
            id: id,
            originalURL: url,
            quarantinedURL: destination,
            requestID: requestID,
            entityID: entityID,
            source: source,
            createdAt: .now
        )
        try JSONEncoder().encode(record).write(to: metadataURL(for: id), options: .atomic)
        return record
    }

    func restore(_ id: UUID) throws -> URL {
        let recordURL = metadataURL(for: id)
        guard FileManager.default.fileExists(atPath: recordURL.path),
              let record = try? JSONDecoder().decode(QuarantineRecord.self, from: Data(contentsOf: recordURL)) else {
            throw QuarantineError.recordNotFound(id)
        }
        guard !FileManager.default.fileExists(atPath: record.originalURL.path) else { throw QuarantineError.destinationExists(record.originalURL) }
        try FileManager.default.moveItem(at: record.quarantinedURL, to: record.originalURL)
        try? FileManager.default.removeItem(at: recordURL)
        return record.originalURL
    }

    /// Tool definitions are deliberately limited to reversible quarantine and
    /// restore operations. A permanent-delete capability is never registered.
    func definitions(
        requestID: UUID,
        entityID: String? = nil,
        source: RequestSource = .commandPalette
    ) -> [ToolDefinition] {
        [
            ToolDefinition(
                name: "files.quarantine",
                effect: .reversibleWrite,
                idempotency: .nonIdempotent,
                requiredArguments: ["path"]
            ) { arguments in
                guard let path = arguments["path"], path.hasPrefix("/") else {
                    throw QuarantineError.missing(URL(fileURLWithPath: arguments["path"] ?? ""))
                }
                let record = try quarantine(
                    URL(fileURLWithPath: path),
                    requestID: requestID,
                    entityID: entityID,
                    source: source
                )
                return .success("Quarantined \(record.originalURL.lastPathComponent).")
            },
            ToolDefinition(
                name: "files.restore",
                effect: .reversibleWrite,
                idempotency: .idempotent,
                requiredArguments: ["id"]
            ) { arguments in
                guard let value = arguments["id"], let id = UUID(uuidString: value) else {
                    throw QuarantineError.recordNotFound(UUID())
                }
                let restored = try restore(id)
                return .success("Restored \(restored.lastPathComponent).")
            }
        ]
    }

    private func metadataURL(for id: UUID) -> URL { rootURL.appendingPathComponent("\(id.uuidString).json") }
}

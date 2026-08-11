import Foundation

struct FileEntity: Codable, Sendable, Equatable, Identifiable {
    let id: String
    var currentURL: URL
    var previousURLs: [URL]
}

struct EntityStore {
    private(set) var files: [String: FileEntity] = [:]

    mutating func register(_ url: URL) throws -> FileEntity {
        let key = try identityKey(for: url)
        if var entity = files[key] {
            if entity.currentURL != url { entity.previousURLs.append(entity.currentURL); entity.currentURL = url }
            files[key] = entity
            return entity
        }
        let entity = FileEntity(id: key, currentURL: url, previousURLs: [])
        files[key] = entity
        return entity
    }

    mutating func update(_ entityID: String, movedTo url: URL) throws -> FileEntity {
        guard var entity = files[entityID] else { throw EntityStoreError.unknownEntity(entityID) }
        if entity.currentURL != url { entity.previousURLs.append(entity.currentURL); entity.currentURL = url }
        files[entityID] = entity
        return entity
    }

    func identityKey(for url: URL) throws -> String {
        if let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
           let identifier = values.fileResourceIdentifier { return "resource:\(identifier)" }
        return "path:\(url.standardizedFileURL.path)"
    }
}

enum EntityStoreError: Error, Equatable { case unknownEntity(String) }

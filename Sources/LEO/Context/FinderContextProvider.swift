import Foundation

struct FinderSelectionEntity: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let fileName: String
    let path: String
    let kind: Kind

    enum Kind: String, Codable, Sendable { case file, directory }
}

protocol FinderSelectionSource: Sendable {
    func selectedItems() async throws -> [URL]
}

struct FinderContextProvider {
    private let source: any FinderSelectionSource

    init(source: some FinderSelectionSource) { self.source = source }

    func currentSelection() async throws -> [FinderSelectionEntity] {
        try await source.selectedItems().map { url in
            let standardized = url.standardizedFileURL
            return FinderSelectionEntity(
                id: "file:\(standardized.path)",
                fileName: standardized.lastPathComponent,
                path: standardized.path,
                kind: (try? standardized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? .directory : .file
            )
        }
    }
}

struct MockFinderSelectionSource: FinderSelectionSource {
    let urls: [URL]
    func selectedItems() async throws -> [URL] { urls }
}

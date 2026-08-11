import Foundation

/// A deliberately small boundary for the current Finder selection. The core
/// receives only the selected file URL, never a broad Finder or AX snapshot.
protocol CurrentFileSelectionProviding: Sendable {
    func selectedFile() async -> URL?
}

struct NoCurrentFileSelection: CurrentFileSelectionProviding {
    func selectedFile() async -> URL? { nil }
}

struct StaticCurrentFileSelection: CurrentFileSelectionProviding {
    let file: URL?
    func selectedFile() async -> URL? { file }
}

import Foundation

struct ModelRequest: Sendable, Equatable {
    let prompt: String
    init(prompt: String) { self.prompt = prompt }
}

struct ModelResourceSnapshot: Sendable, Equatable {
    let isPrepared: Bool
    let activeRequestCount: Int
}

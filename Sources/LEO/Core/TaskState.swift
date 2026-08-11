import Foundation

struct TaskState: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var detail: String?
    var status: Status
    var updatedAt: Date

    enum Status: String, Codable, Sendable { case active, completed, cancelled }

    init(
        id: UUID = UUID(),
        title: String,
        detail: String? = nil,
        status: Status = .active,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.updatedAt = updatedAt
    }
}

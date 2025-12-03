import Foundation
import SwiftData

@Model
final class ChecklistItem {
    var id: UUID
    var text: String
    var isCompleted: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    var note: Note?

    init(
        id: UUID = UUID(),
        text: String = "",
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        note: Note? = nil
    ) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.note = note
    }

    func toggle() {
        isCompleted.toggle()
        updatedAt = Date()
        note?.touch()
    }
}

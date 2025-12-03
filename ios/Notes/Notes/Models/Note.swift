import Foundation
import SwiftData
import SwiftUI

enum NoteType: String, Codable {
    case note
    case checklist
}

enum SyncStatus: String, Codable {
    case synced
    case pending
    case conflict
}

@Model
final class Note {
    var id: UUID
    var title: String
    var content: String
    var noteType: NoteType
    var isPinned: Bool
    var isArchived: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var syncStatus: SyncStatus
    var serverID: String?

    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.note)
    var checklistItems: [ChecklistItem]?

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        noteType: NoteType = .note,
        isPinned: Bool = false,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncStatus: SyncStatus = .pending,
        serverID: String? = nil,
        checklistItems: [ChecklistItem]? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.noteType = noteType
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStatus = syncStatus
        self.serverID = serverID
        self.checklistItems = checklistItems
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        (noteType == .checklist && !(checklistItems?.isEmpty ?? true))
    }

    var sortedChecklistItems: [ChecklistItem] {
        (checklistItems ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var uncheckedItems: [ChecklistItem] {
        sortedChecklistItems.filter { !$0.isCompleted }
    }

    var checkedItems: [ChecklistItem] {
        sortedChecklistItems.filter { $0.isCompleted }
    }

    func touch() {
        updatedAt = Date()
        syncStatus = .pending
    }
}

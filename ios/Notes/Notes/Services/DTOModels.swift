@preconcurrency import Foundation

// MARK: - API Response Models
// These types are intentionally kept in a separate file to avoid
// any main actor inference from SwiftData models.

nonisolated struct APIResponse<T: Codable & Sendable>: Codable, Sendable {
    let success: Bool
    let data: T?
    let error: String?
}

nonisolated struct NoteDTO: Codable, Sendable {
    let id: String
    let title: String
    let content: String
    let noteType: String
    let isPinned: Bool
    let isArchived: Bool
    let sortOrder: Int
    let createdAt: String
    let updatedAt: String
    let checklistItems: [ChecklistItemDTO]?
}

nonisolated struct ChecklistItemDTO: Codable, Sendable {
    let id: String
    let text: String
    let isCompleted: Bool
    let sortOrder: Int
    let createdAt: String
    let updatedAt: String
}

nonisolated struct SyncResponse: Codable, Sendable {
    let notes: [NoteDTO]
    let deletedNoteIDs: [String]
    let serverTimestamp: String
}

nonisolated struct EmptyResponse: Codable, Sendable {}

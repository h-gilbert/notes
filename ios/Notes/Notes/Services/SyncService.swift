import Foundation
import SwiftData
import Combine

// MARK: - Sync State

enum SyncState: Equatable {
    case idle
    case syncing
    case success(Date)
    case error(String)
}

// MARK: - Sync Service

@Observable
@MainActor
final class SyncService {
    static let shared = SyncService()

    private(set) var syncState: SyncState = .idle
    private(set) var lastSyncDate: Date?

    private var modelContext: ModelContext?
    private var syncTask: Task<Void, Never>?
    private var autoSyncTimer: Timer?

    private let userDefaults = UserDefaults.standard
    private let lastSyncKey = "lastSyncDate"
    private let autoSyncInterval: TimeInterval = 60 // 1 minute
    private let reducedSyncInterval: TimeInterval = 300 // 5 minutes when WebSocket connected

    // WebSocket coordination
    private(set) var isWebSocketConnected = false

    private init() {
        lastSyncDate = userDefaults.object(forKey: lastSyncKey) as? Date
    }

    // MARK: - Configuration

    func configure(modelContext: ModelContext, baseURL: String, authToken: String?) async {
        self.modelContext = modelContext
        await APIClient.shared.configure(baseURL: baseURL, authToken: authToken)
    }

    func setAuthToken(_ token: String?) async {
        await APIClient.shared.setAuthToken(token)
    }

    // MARK: - WebSocket Coordination

    func setWebSocketConnected(_ connected: Bool) {
        isWebSocketConnected = connected

        if connected {
            // WebSocket is active - reduce polling frequency (backup only)
            stopAutoSync()
            autoSyncTimer = Timer.scheduledTimer(
                withTimeInterval: reducedSyncInterval,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.sync()
                }
            }
        } else {
            // WebSocket disconnected - resume normal polling and sync immediately
            stopAutoSync()
            startAutoSync()
            Task {
                await sync()
            }
        }
    }

    // MARK: - Auto Sync

    func startAutoSync() {
        stopAutoSync()
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: autoSyncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.sync()
            }
        }
    }

    func stopAutoSync() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
    }

    // MARK: - Manual Sync

    func sync() async {
        guard syncState != .syncing else { return }
        guard let modelContext = modelContext else {
            syncState = .error("Sync service not configured")
            return
        }

        syncState = .syncing

        do {
            // Get pending changes
            let pendingNotes = try fetchPendingNotes(from: modelContext)
            let deletedIDs = try fetchDeletedNoteIDs(from: modelContext)

            // Convert to DTOs
            let noteDTOs = pendingNotes.map { DTOConverter.noteDTO(from: $0) }

            // Sync with server
            let response = try await APIClient.shared.syncNotes(
                changes: noteDTOs,
                deletedIDs: deletedIDs,
                lastSync: lastSyncDate
            )

            // Apply server changes and update serverIDs for pending notes
            try await applyServerChanges(response, to: modelContext, pendingNotes: pendingNotes)

            // Update sync status
            let syncDate = ISO8601DateFormatter().date(from: response.serverTimestamp) ?? Date()
            lastSyncDate = syncDate
            userDefaults.set(syncDate, forKey: lastSyncKey)

            // Mark synced notes (serverID should now be set)
            for note in pendingNotes {
                note.syncStatus = .synced
            }

            // Clear deleted IDs cache
            clearDeletedIDsCache()

            try modelContext.save()

            syncState = .success(syncDate)

        } catch {
            syncState = .error(error.localizedDescription)
        }
    }

    // MARK: - Pending Changes

    private func fetchPendingNotes(from context: ModelContext) throws -> [Note] {
        // Fetch all notes and filter locally since Predicate can't compare enums directly
        let descriptor = FetchDescriptor<Note>()
        let allNotes = try context.fetch(descriptor)
        return allNotes.filter { $0.syncStatus != .synced }
    }

    private func fetchDeletedNoteIDs(from context: ModelContext) throws -> [String] {
        // In a real implementation, you'd store deleted IDs in a separate table
        // For now, return empty array - this would be enhanced with a DeletedNote model
        return userDefaults.stringArray(forKey: "deletedNoteIDs") ?? []
    }

    func markNoteAsDeleted(serverID: String) {
        var deletedIDs = userDefaults.stringArray(forKey: "deletedNoteIDs") ?? []
        if !deletedIDs.contains(serverID) {
            deletedIDs.append(serverID)
            userDefaults.set(deletedIDs, forKey: "deletedNoteIDs")
        }
    }

    private func clearDeletedIDsCache() {
        userDefaults.removeObject(forKey: "deletedNoteIDs")
    }

    // MARK: - Apply Server Changes

    private func applyServerChanges(_ response: SyncResponse, to context: ModelContext, pendingNotes: [Note]) async throws {
        // Fetch all notes with server IDs for comparison
        let allNotesDescriptor = FetchDescriptor<Note>()
        let allNotes = try context.fetch(allNotesDescriptor)

        // Delete notes that were deleted on server
        for deletedID in response.deletedNoteIDs {
            if let noteToDelete = allNotes.first(where: { $0.serverID == deletedID }) {
                context.delete(noteToDelete)
            }
        }

        // Update or create notes from server
        for noteDTO in response.notes {
            try await upsertNote(from: noteDTO, in: context, existingNotes: allNotes, pendingNotes: pendingNotes)
        }
    }

    private func upsertNote(from dto: NoteDTO, in context: ModelContext, existingNotes: [Note], pendingNotes: [Note]) async throws {
        // Try to find existing note by serverID first
        var existingNote = existingNotes.first { $0.serverID == dto.id }

        // If not found by serverID, check if this is a response to a pending note we just uploaded
        // Match by local UUID (pending notes use their local UUID as the ID when sent to server)
        if existingNote == nil {
            existingNote = pendingNotes.first { $0.id.uuidString == dto.id }
        }

        // Also try matching by local UUID in case server preserved it
        if existingNote == nil {
            existingNote = existingNotes.first { $0.id.uuidString == dto.id && $0.serverID == nil }
        }

        let note: Note
        if let existing = existingNote {
            // Check for conflicts (only if note was modified locally after server version)
            let serverDate = ISO8601DateFormatter().date(from: dto.updatedAt) ?? Date()
            if existing.syncStatus == .pending && existing.updatedAt > serverDate {
                // Local changes are newer, mark as conflict but still update serverID
                existing.serverID = dto.id
                existing.syncStatus = .conflict
                return
            }
            note = existing
        } else {
            note = Note()
            context.insert(note)
        }

        // Update note properties
        note.serverID = dto.id
        note.title = dto.title
        note.content = dto.content
        note.noteType = NoteType(rawValue: dto.noteType) ?? .note
        note.isPinned = dto.isPinned
        note.isArchived = dto.isArchived
        note.sortOrder = dto.sortOrder
        note.createdAt = ISO8601DateFormatter().date(from: dto.createdAt) ?? Date()
        note.updatedAt = ISO8601DateFormatter().date(from: dto.updatedAt) ?? Date()
        note.syncStatus = .synced

        // Update checklist items
        if let itemDTOs = dto.checklistItems {
            // Remove existing items
            if let existingItems = note.checklistItems {
                for item in existingItems {
                    context.delete(item)
                }
            }

            // Add new items
            note.checklistItems = itemDTOs.map { itemDTO in
                let item = ChecklistItem(
                    id: UUID(uuidString: itemDTO.id) ?? UUID(),
                    text: itemDTO.text,
                    isCompleted: itemDTO.isCompleted,
                    sortOrder: itemDTO.sortOrder,
                    createdAt: ISO8601DateFormatter().date(from: itemDTO.createdAt) ?? Date(),
                    updatedAt: ISO8601DateFormatter().date(from: itemDTO.updatedAt) ?? Date(),
                    note: note
                )
                context.insert(item)
                return item
            }
        }
    }
}

// MARK: - Sync Status Extension

extension Note {
    var needsSync: Bool {
        syncStatus != .synced
    }

    var hasConflict: Bool {
        syncStatus == .conflict
    }
}

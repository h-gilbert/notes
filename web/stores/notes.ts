import { defineStore } from 'pinia'
import type { Note, NoteDTO, ChecklistItem } from '~/types'
import { api } from '~/utils/api'

interface NotesState {
  notes: Note[]
  lastSyncDate: string | null
  syncState: 'idle' | 'syncing' | 'success' | 'error'
  syncError: string | null
}

export const useNotesStore = defineStore('notes', {
  state: (): NotesState => ({
    notes: [],
    lastSyncDate: null,
    syncState: 'idle',
    syncError: null
  }),

  getters: {
    activeNotes: (state): Note[] =>
      state.notes.filter(n => !n.isArchived).sort((a, b) => a.sortOrder - b.sortOrder),

    archivedNotes: (state): Note[] =>
      state.notes.filter(n => n.isArchived).sort((a, b) =>
        new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
      ),

    pinnedNotes(): Note[] {
      return this.activeNotes.filter(n => n.isPinned)
    },

    unpinnedNotes(): Note[] {
      return this.activeNotes.filter(n => !n.isPinned)
    }
  },

  actions: {
    async fetchNotes() {
      this.syncState = 'syncing'
      this.syncError = null

      try {
        const response = await api.fetchNotes(this.lastSyncDate ?? undefined)

        // Process server notes
        for (const dto of response.notes) {
          this.upsertFromDTO(dto)
        }

        // Remove deleted notes
        for (const id of response.deletedNoteIDs) {
          const index = this.notes.findIndex(n => n.id === id)
          if (index !== -1) {
            this.notes.splice(index, 1)
          }
        }

        this.lastSyncDate = response.serverTimestamp
        this.syncState = 'success'
      } catch (error) {
        this.syncState = 'error'
        this.syncError = error instanceof Error ? error.message : 'Sync failed'
        throw error
      }
    },

    async createNote(noteData: Partial<Note>): Promise<Note> {
      const now = new Date().toISOString()
      const id = crypto.randomUUID()

      // New notes should appear at the top of the unpinned section
      const note: Note = {
        id,
        title: noteData.title ?? '',
        content: noteData.content ?? '',
        noteType: noteData.noteType ?? 'note',
        isPinned: noteData.isPinned ?? false,
        isArchived: false,
        sortOrder: this.getMinUnpinnedSortOrder() - 1,
        createdAt: now,
        updatedAt: now,
        checklistItems: noteData.checklistItems ?? [],
        syncStatus: 'pending'
      }

      this.notes.push(note)

      try {
        const dto = this.noteToDTO(note)
        const created = await api.createNote(dto)
        const index = this.notes.findIndex(n => n.id === id)
        if (index !== -1) {
          this.notes[index] = { ...this.dtoToNote(created), syncStatus: 'synced' }
        }
      } catch {
        // Keep local note with pending status - will retry on next sync
      }

      return note
    },

    async updateNote(note: Note) {
      note.updatedAt = new Date().toISOString()
      note.syncStatus = 'pending'

      const index = this.notes.findIndex(n => n.id === note.id)
      if (index !== -1) {
        this.notes[index] = { ...note }
      }

      try {
        const dto = this.noteToDTO(note)
        const updated = await api.updateNote(dto)
        const idx = this.notes.findIndex(n => n.id === note.id)
        if (idx !== -1) {
          this.notes[idx] = { ...this.dtoToNote(updated), syncStatus: 'synced' }
        }
      } catch {
        // Keep pending status - will retry on next sync
      }
    },

    async deleteNote(id: string) {
      const index = this.notes.findIndex(n => n.id === id)
      if (index !== -1) {
        this.notes.splice(index, 1)
      }

      try {
        await api.deleteNote(id)
      } catch {
        // Deletion will be retried on next sync
      }
    },

    async togglePin(note: Note) {
      note.isPinned = !note.isPinned
      await this.updateNote(note)
    },

    async archiveNote(note: Note) {
      note.isArchived = true
      await this.updateNote(note)
    },

    async unarchiveNote(note: Note) {
      note.isArchived = false
      await this.updateNote(note)
    },

    async reorderNotes(reorderedNotes: Note[]) {
      if (reorderedNotes.length === 0) return

      const now = new Date().toISOString()
      const isPinned = reorderedNotes[0]?.isPinned

      // Get offset for sort order based on section
      // Pinned notes use negative sortOrder, unpinned use positive
      const baseOffset = isPinned ? -reorderedNotes.length : 0

      // Update sort orders locally first
      const updatedNotes: Note[] = []
      reorderedNotes.forEach((note, index) => {
        const storeNote = this.notes.find(n => n.id === note.id)
        if (storeNote) {
          const newSortOrder = baseOffset + index
          if (storeNote.sortOrder !== newSortOrder) {
            storeNote.sortOrder = newSortOrder
            storeNote.updatedAt = now
            storeNote.syncStatus = 'pending'
            updatedNotes.push(storeNote)
          }
        }
      })

      // Sync changed notes to server
      for (const note of updatedNotes) {
        try {
          await api.updateNote(this.noteToDTO(note))
          note.syncStatus = 'synced'
        } catch {
          // Keep pending status
        }
      }
    },

    // Checklist actions
    addChecklistItem(note: Note, text: string) {
      if (!note.checklistItems) {
        note.checklistItems = []
      }

      const maxOrder = note.checklistItems.length > 0
        ? Math.max(...note.checklistItems.map(i => i.sortOrder))
        : -1

      const item: ChecklistItem = {
        id: crypto.randomUUID(),
        text,
        isCompleted: false,
        sortOrder: maxOrder + 1,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      }

      note.checklistItems.push(item)
      this.updateNote(note)
    },

    toggleChecklistItem(note: Note, itemId: string) {
      const item = note.checklistItems?.find(i => i.id === itemId)
      if (item) {
        item.isCompleted = !item.isCompleted
        item.updatedAt = new Date().toISOString()
        this.updateNote(note)
      }
    },

    deleteChecklistItem(note: Note, itemId: string) {
      if (note.checklistItems) {
        note.checklistItems = note.checklistItems.filter(i => i.id !== itemId)
        this.updateNote(note)
      }
    },

    clearCompletedItems(note: Note) {
      if (note.checklistItems) {
        note.checklistItems = note.checklistItems.filter(i => !i.isCompleted)
        this.updateNote(note)
      }
    },

    // Helpers
    getMaxSortOrder(): number {
      if (this.notes.length === 0) return -1
      return Math.max(...this.notes.map(n => n.sortOrder))
    },

    getMinUnpinnedSortOrder(): number {
      const unpinned = this.notes.filter(n => !n.isPinned && !n.isArchived)
      if (unpinned.length === 0) return 0
      return Math.min(...unpinned.map(n => n.sortOrder))
    },

    noteToDTO(note: Note): NoteDTO {
      return {
        id: note.id,
        title: note.title,
        content: note.content,
        noteType: note.noteType,
        isPinned: note.isPinned,
        isArchived: note.isArchived,
        sortOrder: note.sortOrder,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        checklistItems: note.checklistItems
      }
    },

    dtoToNote(dto: NoteDTO): Note {
      return {
        id: dto.id,
        title: dto.title,
        content: dto.content,
        noteType: dto.noteType as 'note' | 'checklist',
        isPinned: dto.isPinned,
        isArchived: dto.isArchived,
        sortOrder: dto.sortOrder,
        createdAt: dto.createdAt,
        updatedAt: dto.updatedAt,
        checklistItems: dto.checklistItems,
        syncStatus: 'synced'
      }
    },

    upsertFromDTO(dto: NoteDTO) {
      const index = this.notes.findIndex(n => n.id === dto.id)
      const note = this.dtoToNote(dto)

      if (index !== -1) {
        // Only update if server version is newer
        if (new Date(dto.updatedAt) > new Date(this.notes[index].updatedAt)) {
          this.notes[index] = note
        }
      } else {
        this.notes.push(note)
      }
    }
  }
})

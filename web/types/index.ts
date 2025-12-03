export type NoteType = 'note' | 'checklist'
export type SyncStatus = 'synced' | 'pending' | 'conflict'

export interface ChecklistItem {
  id: string
  text: string
  isCompleted: boolean
  sortOrder: number
  createdAt: string
  updatedAt: string
}

export interface Note {
  id: string
  title: string
  content: string
  noteType: NoteType
  isPinned: boolean
  isArchived: boolean
  sortOrder: number
  createdAt: string
  updatedAt: string
  checklistItems?: ChecklistItem[]
  syncStatus?: SyncStatus
}

export interface NoteDTO {
  id: string
  title: string
  content: string
  noteType: string
  isPinned: boolean
  isArchived: boolean
  sortOrder: number
  createdAt: string
  updatedAt: string
  checklistItems?: ChecklistItem[]
}

export interface SyncRequest {
  changes: NoteDTO[]
  deletedIDs: string[]
  lastSync?: string
}

export interface SyncResponse {
  notes: NoteDTO[]
  deletedNoteIDs: string[]
  serverTimestamp: string
}

export interface User {
  id: string
  username: string
}

export interface AuthRequest {
  username: string
  password: string
}

export interface AuthResponse {
  token: string
  user: User
}

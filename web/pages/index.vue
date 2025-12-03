<template>
  <div class="home">
    <!-- Pinned section -->
    <section v-if="pinnedNotes.length > 0" class="section">
      <div class="section-header">
        <svg class="pin-icon" width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path d="M16 12V4h1V2H7v2h1v8l-2 2v2h5v6l1 1 1-1v-6h5v-2l-2-2z"/>
        </svg>
        <span class="section-label">PINNED</span>
      </div>
      <NotesList :notes="pinnedNotes" @select="openNote" @update="handleUpdate" @reorder="handleReorder" />
    </section>

    <!-- Notes section -->
    <section v-if="unpinnedNotes.length > 0" class="section">
      <div v-if="pinnedNotes.length > 0" class="section-header">
        <span class="section-label text-tertiary">NOTES</span>
      </div>
      <NotesList :notes="unpinnedNotes" @select="openNote" @update="handleUpdate" @reorder="handleReorder" />
    </section>

    <!-- Empty state -->
    <div v-if="pinnedNotes.length === 0 && unpinnedNotes.length === 0" class="empty-state">
      <svg class="empty-icon" width="48" height="48" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <path d="M14 2H6c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/>
      </svg>
      <h2>Your canvas awaits</h2>
      <p>Tap below to capture your first thought</p>
    </div>

    <!-- Create note bar -->
    <CreateNoteBar @create="handleCreateNote" />

    <!-- Note editor modal -->
    <NoteEditor
      v-if="selectedNote"
      :note="selectedNote"
      @close="closeNote"
      @save="handleSave"
      @delete="handleDelete"
    />
  </div>
</template>

<script setup lang="ts">
import type { Note } from '~/types'

definePageMeta({
  middleware: 'auth',
  ssr: false
})

const notesStore = useNotesStore()

const selectedNote = ref<Note | null>(null)

const pinnedNotes = computed(() => notesStore.pinnedNotes)
const unpinnedNotes = computed(() => notesStore.unpinnedNotes)

// Fetch notes on mount
onMounted(async () => {
  try {
    await notesStore.fetchNotes()
  } catch (error) {
    console.error('Failed to fetch notes:', error)
  }
})

const openNote = (note: Note) => {
  selectedNote.value = { ...note }
}

const closeNote = () => {
  selectedNote.value = null
}

const handleCreateNote = async (type: 'note' | 'checklist') => {
  const note = await notesStore.createNote({ noteType: type })
  openNote(note)
}

const handleSave = async (note: Note) => {
  await notesStore.updateNote(note)
  closeNote()
}

const handleDelete = async (note: Note) => {
  await notesStore.deleteNote(note.id)
  closeNote()
}

const handleUpdate = async (note: Note) => {
  await notesStore.updateNote(note)
}

const handleReorder = async (notes: Note[]) => {
  await notesStore.reorderNotes(notes)
}
</script>

<style scoped>
.home {
  padding-bottom: 80px;
}

.section {
  margin-bottom: var(--spacing-lg);
}

.section-header {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-bottom: var(--spacing-sm);
}

.pin-icon {
  color: var(--color-accent);
}

.section-label {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 1px;
  color: var(--color-accent);
}

.empty-state {
  text-align: center;
  padding: var(--spacing-xxl) var(--spacing-md);
}

.empty-icon {
  margin-bottom: var(--spacing-md);
  color: var(--color-text-tertiary);
}

.empty-state h2 {
  font-size: 22px;
  font-weight: 600;
  color: var(--color-text-primary);
  margin-bottom: var(--spacing-xs);
}

.empty-state p {
  color: var(--color-text-secondary);
}
</style>

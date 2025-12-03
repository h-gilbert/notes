<template>
  <div class="archive">
    <h1 class="page-title">Archive</h1>

    <MasonryNotesList
      v-if="archivedNotes.length > 0"
      :notes="archivedNotes"
      :is-archived="true"
      @select="openNote"
      @update="handleUpdate"
    />

    <div v-else class="empty-state">
      <svg class="empty-icon" width="48" height="48" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <path d="M20.54 5.23l-1.39-1.68C18.88 3.21 18.47 3 18 3H6c-.47 0-.88.21-1.16.55L3.46 5.23C3.17 5.57 3 6.02 3 6.5V19c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V6.5c0-.48-.17-.93-.46-1.27zM12 17.5L6.5 12H10v-2h4v2h3.5L12 17.5zM5.12 5l.81-1h12l.94 1H5.12z"/>
      </svg>
      <h2>No archived notes</h2>
      <p>Archived notes will appear here</p>
    </div>

    <!-- Note editor modal -->
    <NoteEditor
      v-if="selectedNote"
      :note="selectedNote"
      :is-archived="true"
      @close="closeNote"
      @save="handleSave"
      @delete="handleDelete"
      @unarchive="handleUnarchive"
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

const archivedNotes = computed(() => notesStore.archivedNotes)

const openNote = (note: Note) => {
  selectedNote.value = { ...note }
}

const closeNote = () => {
  selectedNote.value = null
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

const handleUnarchive = async (note: Note) => {
  await notesStore.unarchiveNote(note)
  closeNote()
}
</script>

<style scoped>
.archive {
  padding-bottom: var(--spacing-xl);
}

.page-title {
  font-size: 28px;
  font-weight: 700;
  margin-bottom: var(--spacing-lg);
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

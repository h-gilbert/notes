<template>
  <div class="home">
    <!-- Reorder mode toggle -->
    <div v-if="pinnedNotes.length > 0 || unpinnedNotes.length > 0" class="reorder-toggle">
      <button @click="isReorderMode = !isReorderMode" class="reorder-btn">
        <svg v-if="!isReorderMode" width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path d="M3 15h18v-2H3v2zm0 4h18v-2H3v2zm0-8h18V9H3v2zm0-6v2h18V5H3z"/>
        </svg>
        <span>{{ isReorderMode ? 'Done' : 'Reorder' }}</span>
      </button>
    </div>

    <!-- Reorder mode view -->
    <template v-if="isReorderMode">
      <div class="reorder-mode">
        <section v-if="pinnedNotes.length > 0" class="section">
          <div class="section-header">
            <svg class="pin-icon" width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M16 12V4h1V2H7v2h1v8l-2 2v2h5v6l1 1 1-1v-6h5v-2l-2-2z"/>
            </svg>
            <span class="section-label">PINNED</span>
          </div>
          <NotesList :notes="pinnedNotes" @select="openNote" @update="handleUpdate" @reorder="handleReorderPinned" />
        </section>

        <section v-if="unpinnedNotes.length > 0" class="section">
          <div class="section-header">
            <span class="section-label text-tertiary">NOTES</span>
          </div>
          <NotesList :notes="unpinnedNotes" @select="openNote" @update="handleUpdate" @reorder="handleReorderUnpinned" />
        </section>
      </div>
    </template>

    <!-- Normal mosaic view -->
    <template v-else>
      <!-- Pinned section -->
      <section v-if="pinnedNotes.length > 0" class="section">
        <div class="section-header">
          <svg class="pin-icon" width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M16 12V4h1V2H7v2h1v8l-2 2v2h5v6l1 1 1-1v-6h5v-2l-2-2z"/>
          </svg>
          <span class="section-label">PINNED</span>
        </div>
        <MasonryNotesList :notes="pinnedNotes" @select="openNote" @update="handleUpdate" />
      </section>

      <!-- Notes section -->
      <section v-if="unpinnedNotes.length > 0" class="section">
        <div v-if="pinnedNotes.length > 0" class="section-header">
          <span class="section-label text-tertiary">NOTES</span>
        </div>
        <MasonryNotesList :notes="unpinnedNotes" @select="openNote" @update="handleUpdate" />
      </section>
    </template>

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
      :focus-content="focusContent"
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
const focusContent = ref(false)
const isReorderMode = ref(false)

const pinnedNotes = computed(() => notesStore.pinnedNotes)
const unpinnedNotes = computed(() => notesStore.unpinnedNotes)

// Handle global keydown to start typing a new note
const handleGlobalKeydown = async (e: KeyboardEvent) => {
  // Ignore if note editor is already open
  if (selectedNote.value) return

  // Ignore if user is focused on an input, textarea, or contenteditable
  const target = e.target as HTMLElement
  if (
    target.tagName === 'INPUT' ||
    target.tagName === 'TEXTAREA' ||
    target.isContentEditable
  ) return

  // Ignore modifier keys alone, function keys, and special keys
  if (
    e.metaKey || e.ctrlKey || e.altKey ||
    e.key === 'Shift' || e.key === 'Control' || e.key === 'Alt' || e.key === 'Meta' ||
    e.key === 'Tab' || e.key === 'Escape' || e.key === 'Enter' ||
    e.key === 'Backspace' || e.key === 'Delete' ||
    e.key.startsWith('Arrow') || e.key.startsWith('F') ||
    e.key === 'Home' || e.key === 'End' || e.key === 'PageUp' || e.key === 'PageDown'
  ) return

  // Only proceed with printable characters (single character keys)
  if (e.key.length !== 1) return

  // Prevent the character from being typed elsewhere
  e.preventDefault()

  // Create a new note with the initial character
  const note = await notesStore.createNote({
    noteType: 'note',
    content: e.key
  })
  openNote(note, true)  // Focus content since user started typing
}

// Fetch notes on mount
onMounted(async () => {
  document.addEventListener('keydown', handleGlobalKeydown)

  try {
    await notesStore.fetchNotes()
  } catch (error) {
    console.error('Failed to fetch notes:', error)
  }
})

onUnmounted(() => {
  document.removeEventListener('keydown', handleGlobalKeydown)
})

const openNote = (note: Note, shouldFocusContent = false) => {
  selectedNote.value = { ...note }
  focusContent.value = shouldFocusContent
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

const handleReorderPinned = async (notes: Note[]) => {
  await notesStore.reorderNotes(notes)
}

const handleReorderUnpinned = async (notes: Note[]) => {
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

.reorder-toggle {
  display: flex;
  justify-content: flex-end;
  margin-bottom: var(--spacing-md);
}

.reorder-btn {
  display: flex;
  align-items: center;
  gap: var(--spacing-xs);
  padding: var(--spacing-xs) var(--spacing-sm);
  font-size: 14px;
  font-weight: 500;
  color: var(--color-text-secondary);
  border-radius: var(--radius-small);
  transition: all 0.2s ease;
}

.reorder-btn:hover {
  background-color: var(--color-background-secondary);
  color: var(--color-text-primary);
}

.reorder-btn svg {
  color: var(--color-text-tertiary);
}

.reorder-mode {
  max-width: 600px;
  margin: 0 auto;
}
</style>

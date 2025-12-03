<template>
  <div class="editor-overlay" @click.self="handleClose">
    <div class="editor card">
      <!-- Header -->
      <div class="editor-header">
        <button class="close-btn" @click="handleClose">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/>
          </svg>
        </button>
        <div class="header-actions">
          <button v-if="!isArchived" @click="handlePin" class="action-btn" :class="{ pinned: localNote.isPinned }">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M16 12V4h1V2H7v2h1v8l-2 2v2h5v6l1 1 1-1v-6h5v-2l-2-2z"/>
            </svg>
          </button>
          <button class="menu-btn" @click.stop="showMenu = !showMenu">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <circle cx="12" cy="5" r="2"/>
              <circle cx="12" cy="12" r="2"/>
              <circle cx="12" cy="19" r="2"/>
            </svg>
          </button>
        </div>

        <!-- Menu dropdown -->
        <div v-if="showMenu" class="dropdown-menu" @click.stop>
          <button v-if="!isArchived" @click="handleArchive">Archive</button>
          <button v-if="isArchived" @click="$emit('unarchive', localNote)">Unarchive</button>
          <button
            v-if="localNote.noteType === 'checklist' && checkedItems.length > 0"
            @click="handleClearCompleted"
          >
            Clear completed
          </button>
          <button class="danger" @click="handleDelete">Delete</button>
        </div>
      </div>

      <!-- Content -->
      <div class="editor-content">
        <input
          v-model="localNote.title"
          type="text"
          class="title-input"
          placeholder="Title"
          @input="markDirty"
        />

        <!-- Text note content -->
        <textarea
          v-if="localNote.noteType === 'note'"
          v-model="localNote.content"
          class="content-input"
          placeholder="Start writing..."
          @input="markDirty"
        ></textarea>

        <!-- Checklist content -->
        <div v-else class="checklist-content">
          <!-- Unchecked items -->
          <div
            v-for="item in uncheckedItems"
            :key="item.id"
            class="checklist-row"
          >
            <button class="checkbox" @click="toggleItem(item.id)"></button>
            <input
              v-model="item.text"
              type="text"
              class="item-input"
              @input="markDirty"
            />
            <button class="delete-item" @click="deleteItem(item.id)">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                <path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/>
              </svg>
            </button>
          </div>

          <!-- Add item -->
          <div class="checklist-row add-row">
            <span class="checkbox add-checkbox"></span>
            <input
              v-model="newItemText"
              type="text"
              class="item-input"
              placeholder="Add item"
              @keypress.enter="addItem"
            />
          </div>

          <!-- Checked items -->
          <div v-if="checkedItems.length > 0" class="checked-section">
            <div class="checked-header">
              {{ checkedItems.length }} completed
            </div>
            <div
              v-for="item in checkedItems"
              :key="item.id"
              class="checklist-row checked"
            >
              <button class="checkbox checked" @click="toggleItem(item.id)">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                  <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>
                </svg>
              </button>
              <input
                v-model="item.text"
                type="text"
                class="item-input"
                @input="markDirty"
              />
              <button class="delete-item" @click="deleteItem(item.id)">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                  <path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/>
                </svg>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { Note, ChecklistItem } from '~/types'

const props = defineProps<{
  note: Note
  isArchived?: boolean
}>()

const emit = defineEmits<{
  close: []
  save: [note: Note]
  delete: [note: Note]
  unarchive: [note: Note]
}>()

const notesStore = useNotesStore()
const localNote = ref<Note>({ ...props.note })
const showMenu = ref(false)
const newItemText = ref('')
const isDirty = ref(false)

const uncheckedItems = computed(() =>
  (localNote.value.checklistItems ?? [])
    .filter(i => !i.isCompleted)
    .sort((a, b) => a.sortOrder - b.sortOrder)
)

const checkedItems = computed(() =>
  (localNote.value.checklistItems ?? [])
    .filter(i => i.isCompleted)
    .sort((a, b) => a.sortOrder - b.sortOrder)
)

const isNoteEmpty = computed(() => {
  const hasTitle = localNote.value.title?.trim()
  const hasContent = localNote.value.content?.trim()
  const hasChecklistItems = (localNote.value.checklistItems ?? []).some(item => item.text?.trim())
  return !hasTitle && !hasContent && !hasChecklistItems
})

const markDirty = () => {
  isDirty.value = true
}

const handleClose = () => {
  if (isNoteEmpty.value) {
    // Delete empty notes instead of saving them
    emit('delete', localNote.value)
  } else if (isDirty.value) {
    emit('save', localNote.value)
  } else {
    emit('close')
  }
}

const handlePin = () => {
  localNote.value.isPinned = !localNote.value.isPinned
  markDirty()
}

const handleArchive = () => {
  showMenu.value = false
  localNote.value.isArchived = true
  emit('save', localNote.value)
}

const handleDelete = () => {
  showMenu.value = false
  emit('delete', localNote.value)
}

const handleClearCompleted = () => {
  showMenu.value = false
  if (localNote.value.checklistItems) {
    localNote.value.checklistItems = localNote.value.checklistItems.filter(i => !i.isCompleted)
    markDirty()
  }
}

const addItem = () => {
  if (!newItemText.value.trim()) return

  if (!localNote.value.checklistItems) {
    localNote.value.checklistItems = []
  }

  const maxOrder = localNote.value.checklistItems.length > 0
    ? Math.max(...localNote.value.checklistItems.map(i => i.sortOrder))
    : -1

  const item: ChecklistItem = {
    id: crypto.randomUUID(),
    text: newItemText.value.trim(),
    isCompleted: false,
    sortOrder: maxOrder + 1,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString()
  }

  localNote.value.checklistItems.push(item)
  newItemText.value = ''
  markDirty()
}

const toggleItem = (id: string) => {
  const item = localNote.value.checklistItems?.find(i => i.id === id)
  if (item) {
    item.isCompleted = !item.isCompleted
    item.updatedAt = new Date().toISOString()
    markDirty()
  }
}

const deleteItem = (id: string) => {
  if (localNote.value.checklistItems) {
    localNote.value.checklistItems = localNote.value.checklistItems.filter(i => i.id !== id)
    markDirty()
  }
}

// Close menu on outside click
onMounted(() => {
  document.addEventListener('click', (e) => {
    if (showMenu.value) {
      showMenu.value = false
    }
  })
})
</script>

<style scoped>
.editor-overlay {
  position: fixed;
  inset: 0;
  background-color: rgba(0, 0, 0, 0.4);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: var(--spacing-md);
  z-index: 200;
}

.editor {
  width: 100%;
  max-width: 600px;
  max-height: 80vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.editor-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--spacing-md);
  border-bottom: 1px solid var(--color-shadow-light);
  position: relative;
}

.close-btn {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--color-text-secondary);
}

.close-btn:hover {
  background-color: var(--color-background-secondary);
}

.header-actions {
  display: flex;
  gap: var(--spacing-xs);
}

.action-btn, .menu-btn {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--color-text-secondary);
}

.action-btn.pinned {
  color: var(--color-accent);
}

.action-btn:hover, .menu-btn:hover {
  background-color: var(--color-background-secondary);
}

.dropdown-menu {
  position: absolute;
  top: 56px;
  right: var(--spacing-md);
  background-color: var(--color-surface);
  border-radius: var(--radius-small);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  padding: var(--spacing-xs);
  z-index: 10;
}

.dropdown-menu button {
  display: block;
  width: 100%;
  padding: var(--spacing-xs) var(--spacing-sm);
  text-align: left;
  font-size: 14px;
  border-radius: 6px;
  white-space: nowrap;
}

.dropdown-menu button:hover {
  background-color: var(--color-background-secondary);
}

.dropdown-menu button.danger {
  color: var(--color-danger);
}

.editor-content {
  flex: 1;
  overflow-y: auto;
  padding: var(--spacing-md);
}

.title-input {
  width: 100%;
  font-size: 22px;
  font-weight: 600;
  color: var(--color-text-primary);
  margin-bottom: var(--spacing-md);
}

.title-input::placeholder {
  color: var(--color-text-tertiary);
}

.content-input {
  width: 100%;
  min-height: 200px;
  font-size: 16px;
  color: var(--color-text-secondary);
  line-height: 1.6;
  resize: none;
}

.content-input::placeholder {
  color: var(--color-text-tertiary);
}

.checklist-content {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.checklist-row {
  display: flex;
  align-items: center;
  gap: var(--spacing-sm);
  padding: var(--spacing-xs) 0;
}

.checkbox {
  width: 22px;
  height: 22px;
  border: 2px solid var(--color-accent);
  border-radius: 50%;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  opacity: 0.6;
}

.checkbox.checked {
  background-color: var(--color-accent);
}

.add-checkbox {
  border-style: dashed;
  opacity: 0.4;
}

.item-input {
  flex: 1;
  font-size: 16px;
  color: var(--color-text-primary);
}

.checklist-row.checked .item-input {
  text-decoration: line-through;
  color: var(--color-text-tertiary);
}

.delete-item {
  width: 24px;
  height: 24px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--color-text-tertiary);
  opacity: 0;
}

.checklist-row:hover .delete-item {
  opacity: 1;
}

.delete-item:hover {
  background-color: var(--color-background-secondary);
  color: var(--color-danger);
}

.checked-section {
  margin-top: var(--spacing-md);
  padding-top: var(--spacing-md);
  border-top: 1px solid var(--color-shadow-light);
}

.checked-header {
  font-size: 12px;
  font-weight: 500;
  color: var(--color-text-tertiary);
  margin-bottom: var(--spacing-xs);
}
</style>

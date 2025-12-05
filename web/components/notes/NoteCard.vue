<template>
  <div class="note-card card" :class="{ 'menu-open': showMenu }" @click="$emit('select', note)">
    <!-- Title -->
    <h3 v-if="note.title" class="title">{{ note.title }}</h3>

    <!-- Content or checklist preview -->
    <div v-if="note.noteType === 'checklist'" class="checklist-preview">
      <div
        v-for="item in uncheckedItems.slice(0, 4)"
        :key="item.id"
        class="checklist-item"
      >
        <span class="checkbox"></span>
        <span class="item-text">{{ item.text }}</span>
      </div>
      <div v-if="uncheckedItems.length > 4" class="more-items">
        +{{ uncheckedItems.length - 4 }} more
      </div>
      <div v-if="checkedItems.length > 0" class="completed-count">
        <span class="check-icon">
          <svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>
          </svg>
        </span>
        {{ checkedItems.length }} completed
      </div>
    </div>
    <p v-else-if="note.content" class="content" :class="{ 'content-only': !note.title }">{{ note.content }}</p>

    <!-- Context menu trigger -->
    <button class="menu-btn" @click.stop="showMenu = !showMenu">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <circle cx="12" cy="5" r="2"/>
        <circle cx="12" cy="12" r="2"/>
        <circle cx="12" cy="19" r="2"/>
      </svg>
    </button>

    <!-- Context menu -->
    <div v-if="showMenu" class="context-menu" @click.stop>
      <button v-if="!isArchived" @click="handlePin">
        {{ note.isPinned ? 'Unpin' : 'Pin' }}
      </button>
      <button v-if="!isArchived" @click="handleArchive">Archive</button>
      <button v-if="isArchived" @click="handleUnarchive">Unarchive</button>
      <button class="danger" @click="handleDelete">Delete</button>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { Note } from '~/types'

const props = defineProps<{
  note: Note
  isArchived?: boolean
}>()

const emit = defineEmits<{
  select: [note: Note]
  update: [note: Note]
  delete: [note: Note]
}>()

const notesStore = useNotesStore()
const showMenu = ref(false)

const uncheckedItems = computed(() =>
  (props.note.checklistItems ?? [])
    .filter(i => !i.isCompleted)
    .sort((a, b) => a.sortOrder - b.sortOrder)
)

const checkedItems = computed(() =>
  (props.note.checklistItems ?? []).filter(i => i.isCompleted)
)

const handlePin = async () => {
  showMenu.value = false
  await notesStore.togglePin(props.note)
}

const handleArchive = async () => {
  showMenu.value = false
  const scrollY = window.scrollY
  await notesStore.archiveNote(props.note)
  await nextTick()
  window.scrollTo(0, scrollY)
}

const handleUnarchive = async () => {
  showMenu.value = false
  const scrollY = window.scrollY
  await notesStore.unarchiveNote(props.note)
  await nextTick()
  window.scrollTo(0, scrollY)
}

const handleDelete = async () => {
  showMenu.value = false
  const scrollY = window.scrollY
  await notesStore.deleteNote(props.note.id)
  await nextTick()
  window.scrollTo(0, scrollY)
}

// Close menu when clicking outside
onMounted(() => {
  document.addEventListener('click', () => {
    showMenu.value = false
  })
})
</script>

<style scoped>
.note-card {
  padding: var(--spacing-md);
  cursor: pointer;
  position: relative;
  transition: transform 0.2s ease, box-shadow 0.2s ease;
  z-index: 1;
}

.note-card.menu-open {
  z-index: 100;
}

.note-card:hover {
  transform: translateY(-2px);
  box-shadow:
    0 8px 16px var(--color-shadow-light),
    0 2px 4px var(--color-shadow-medium);
}

.title {
  font-size: 17px;
  font-weight: 600;
  color: var(--color-text-primary);
  margin-bottom: var(--spacing-xs);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.content {
  font-size: 14px;
  color: var(--color-text-secondary);
  line-height: 1.5;
  display: -webkit-box;
  -webkit-line-clamp: 10;
  -webkit-box-orient: vertical;
  overflow: hidden;
  white-space: pre-wrap;
  word-break: break-word;
}

.content.content-only {
  font-size: 16px;
  color: var(--color-text-primary);
  -webkit-line-clamp: 12;
}

.checklist-preview {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.checklist-item {
  display: flex;
  align-items: center;
  gap: 10px;
}

.checkbox {
  width: 16px;
  height: 16px;
  border: 1.5px solid var(--color-accent);
  border-radius: 50%;
  flex-shrink: 0;
  opacity: 0.6;
}

.item-text {
  font-size: 14px;
  color: var(--color-text-primary);
  overflow-wrap: break-word;
  word-break: break-word;
  line-height: 1.4;
}

.more-items {
  font-size: 11px;
  color: var(--color-text-tertiary);
  padding-left: 26px;
}

.completed-count {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 11px;
  color: var(--color-text-tertiary);
  margin-top: 4px;
}

.check-icon {
  width: 16px;
  height: 16px;
  background-color: var(--color-accent);
  color: white;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  opacity: 0.6;
}

.menu-btn {
  position: absolute;
  top: var(--spacing-sm);
  right: var(--spacing-sm);
  width: 28px;
  height: 28px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--color-text-tertiary);
  opacity: 0;
  transition: opacity 0.2s ease;
}

.note-card:hover .menu-btn {
  opacity: 1;
}

.menu-btn:hover {
  background-color: var(--color-background-secondary);
}

.context-menu {
  position: absolute;
  top: 40px;
  right: var(--spacing-sm);
  background-color: var(--color-surface);
  border-radius: var(--radius-small);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  padding: var(--spacing-xs);
  z-index: 101;
}

.context-menu button {
  display: block;
  width: 100%;
  padding: var(--spacing-xs) var(--spacing-sm);
  text-align: left;
  font-size: 14px;
  border-radius: 6px;
}

.context-menu button:hover {
  background-color: var(--color-background-secondary);
}

.context-menu button.danger {
  color: var(--color-danger);
}
</style>

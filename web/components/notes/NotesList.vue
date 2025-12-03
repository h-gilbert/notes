<template>
  <draggable
    :model-value="notes"
    item-key="id"
    class="notes-list"
    :animation="200"
    ghost-class="note-ghost"
    drag-class="note-drag"
    @update:model-value="onReorder"
  >
    <template #item="{ element: note }">
      <NoteCard
        :note="note"
        :is-archived="isArchived"
        @select="$emit('select', note)"
        @update="$emit('update', $event)"
      />
    </template>
  </draggable>
</template>

<script setup lang="ts">
import draggable from 'vuedraggable'
import type { Note } from '~/types'

defineProps<{
  notes: Note[]
  isArchived?: boolean
}>()

const emit = defineEmits<{
  select: [note: Note]
  update: [note: Note]
  reorder: [notes: Note[]]
}>()

const onReorder = (newNotes: Note[]) => {
  emit('reorder', newNotes)
}
</script>

<style scoped>
.notes-list {
  display: flex;
  flex-direction: column;
  gap: var(--spacing-sm);
}

.note-ghost {
  opacity: 0.4;
}

.note-drag {
  opacity: 0.9;
  cursor: grabbing;
}
</style>

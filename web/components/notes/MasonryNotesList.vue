<template>
  <MasonryWall
    :items="notes"
    :column-width="200"
    :gap="12"
    :ssr-columns="2"
  >
    <template #default="{ item: note }">
      <NoteCard
        :note="note"
        :is-archived="isArchived"
        @select="$emit('select', note)"
        @update="$emit('update', $event)"
      />
    </template>
  </MasonryWall>
</template>

<script setup lang="ts">
import MasonryWall from '@yeger/vue-masonry-wall'
import type { Note } from '~/types'

defineProps<{
  notes: Note[]
  isArchived?: boolean
}>()

defineEmits<{
  select: [note: Note]
  update: [note: Note]
}>()
</script>

<style scoped>
:deep(.masonry-wall) {
  display: flex;
  gap: var(--spacing-sm);
}

:deep(.masonry-column) {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: var(--spacing-sm);
}
</style>

<template>
  <div class="create-bar-container">
    <div class="create-bar card">
      <button class="create-btn" @click="$emit('create', 'note')">
        <span class="plus-icon">+</span>
        <span>Take a note...</span>
      </button>
      <button class="checklist-btn" @click="$emit('create', 'checklist')" title="New checklist">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V5h14v14zM17.99 9l-1.41-1.42-6.59 6.59-2.58-2.57-1.42 1.41 4 3.99z"/>
        </svg>
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
defineEmits<{
  create: [type: 'note' | 'checklist']
}>()
</script>

<style scoped>
.create-bar-container {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  padding: var(--spacing-md);
  background: linear-gradient(transparent, var(--color-background) 30%);
  pointer-events: none;
}

.create-bar {
  max-width: 768px;
  margin: 0 auto;
  display: flex;
  align-items: center;
  padding: var(--spacing-sm) var(--spacing-md);
  pointer-events: auto;
}

.create-btn {
  flex: 1;
  display: flex;
  align-items: center;
  gap: var(--spacing-sm);
  padding: var(--spacing-sm);
  text-align: left;
}

.plus-icon {
  width: 24px;
  height: 24px;
  background-color: var(--color-accent);
  color: white;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  font-weight: 500;
}

.create-btn span:last-child {
  color: var(--color-text-tertiary);
  font-size: 16px;
}

.checklist-btn {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--color-text-secondary);
}

.checklist-btn:hover {
  background-color: var(--color-background-secondary);
}
</style>

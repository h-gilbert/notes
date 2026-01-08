<template>
  <header class="app-header">
    <div class="header-content">
      <div class="logo-section">
        <h1 class="logo">Notes</h1>
        <ClientOnly>
          <span
            class="sync-indicator"
            :class="connectionStatus"
            :title="connectionTitle"
          ></span>
        </ClientOnly>
      </div>
      <nav class="nav-links">
        <NuxtLink to="/" class="nav-link" :class="{ active: route.path === '/' }">
          Notes
        </NuxtLink>
        <NuxtLink to="/archive" class="nav-link" :class="{ active: route.path === '/archive' }">
          Archive
        </NuxtLink>
        <NuxtLink to="/settings" class="nav-link" :class="{ active: route.path === '/settings' }">
          Settings
        </NuxtLink>
        <button @click="handleLogout" class="logout-btn">
          Logout
        </button>
      </nav>
    </div>
  </header>
</template>

<script setup lang="ts">
const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const { connectionStatus } = useWebSocket()

const connectionTitle = computed(() => {
  switch (connectionStatus.value) {
    case 'connected':
      return 'Real-time sync active'
    case 'connecting':
      return 'Connecting...'
    case 'disconnected':
      return 'Offline - changes will sync when reconnected'
    default:
      return ''
  }
})

const handleLogout = () => {
  authStore.logout()
  router.push('/login')
}
</script>

<style scoped>
.app-header {
  background-color: var(--color-surface);
  border-bottom: 1px solid var(--color-shadow-light);
  position: sticky;
  top: 0;
  z-index: 100;
}

.header-content {
  max-width: 800px;
  margin: 0 auto;
  padding: var(--spacing-md);
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.logo-section {
  display: flex;
  align-items: center;
  gap: var(--spacing-xs);
}

.logo {
  font-size: 24px;
  font-weight: 700;
  color: var(--color-text-primary);
}

.sync-indicator {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  transition: background-color 0.3s ease;
}

.sync-indicator.connected {
  background-color: #4CAF50;
}

.sync-indicator.connecting {
  background-color: #FFC107;
  animation: pulse 1s ease-in-out infinite;
}

.sync-indicator.disconnected {
  background-color: var(--color-text-tertiary);
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

.nav-links {
  display: flex;
  align-items: center;
  gap: var(--spacing-md);
}

.nav-link {
  font-size: 15px;
  font-weight: 500;
  color: var(--color-text-secondary);
  padding: var(--spacing-xs) var(--spacing-sm);
  border-radius: var(--radius-small);
  transition: all 0.2s ease;
}

.nav-link:hover {
  color: var(--color-text-primary);
  background-color: var(--color-background-secondary);
}

.nav-link.active {
  color: var(--color-accent);
}

.logout-btn {
  font-size: 14px;
  color: var(--color-text-secondary);
  padding: var(--spacing-xs) var(--spacing-sm);
}

.logout-btn:hover {
  color: var(--color-danger);
}
</style>

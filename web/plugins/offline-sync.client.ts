export default defineNuxtPlugin(async () => {
  const notesStore = useNotesStore()
  const authStore = useAuthStore()
  const { isOnline } = useNetworkStatus()

  // Hydrate store from IndexedDB cached data
  await notesStore.initFromDB()

  // When connectivity is restored, sync pending changes
  watch(isOnline, async (online) => {
    if (online && authStore.isAuthenticated && authStore.accessToken) {
      try {
        await notesStore.syncPendingChanges()
      } catch {
        // Sync will retry on next connectivity change
      }
    }
  })
})

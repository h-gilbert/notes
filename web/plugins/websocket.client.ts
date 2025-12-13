export default defineNuxtPlugin(() => {
  const authStore = useAuthStore()
  const { connect, disconnect, connectionStatus } = useWebSocket()

  // Track the last token we connected with to avoid duplicate connections
  let lastConnectedToken: string | null = null

  // Load stored auth on startup
  authStore.loadStoredAuth()

  // Single watcher for both auth state and token changes
  watch(
    () => ({ isAuthenticated: authStore.isAuthenticated, token: authStore.token }),
    ({ isAuthenticated, token }) => {
      if (isAuthenticated && token) {
        // Only connect if token changed or we're not already connected/connecting
        if (token !== lastConnectedToken && connectionStatus.value === 'disconnected') {
          lastConnectedToken = token
          connect(token)
        } else if (token !== lastConnectedToken && connectionStatus.value === 'connected') {
          // Token changed while connected - reconnect with new token
          lastConnectedToken = token
          disconnect()
          connect(token)
        }
      } else {
        // Not authenticated - disconnect
        lastConnectedToken = null
        disconnect()
      }
    },
    { immediate: true }
  )
})

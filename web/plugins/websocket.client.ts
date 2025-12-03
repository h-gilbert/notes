export default defineNuxtPlugin(() => {
  const authStore = useAuthStore()
  const { connect, disconnect } = useWebSocket()

  // Load stored auth on startup
  authStore.loadStoredAuth()

  // Connect if already authenticated
  if (authStore.isAuthenticated && authStore.token) {
    connect(authStore.token)
  }

  // Watch for auth state changes
  watch(
    () => authStore.isAuthenticated,
    (isAuthenticated) => {
      if (isAuthenticated && authStore.token) {
        connect(authStore.token)
      } else {
        disconnect()
      }
    }
  )

  // Watch for token changes (e.g., token refresh)
  watch(
    () => authStore.token,
    (newToken, oldToken) => {
      if (newToken && newToken !== oldToken) {
        // Reconnect with new token
        disconnect()
        connect(newToken)
      }
    }
  )
})

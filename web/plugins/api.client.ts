import { api } from '~/utils/api'

export default defineNuxtPlugin(() => {
  const config = useRuntimeConfig()
  const authStore = useAuthStore()

  // Configure API base URL
  api.configure(config.public.apiBase as string)

  // Set token if available
  if (authStore.token) {
    api.setToken(authStore.token)
  }

  // Watch for token changes
  watch(
    () => authStore.token,
    (newToken) => {
      if (newToken) {
        api.setToken(newToken)
      }
    }
  )
})

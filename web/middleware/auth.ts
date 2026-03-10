export default defineNuxtRouteMiddleware(async (to) => {
  const authStore = useAuthStore()

  // Ensure auth state is loaded from cookies before checking
  // This is needed because middleware may run before app.vue setup
  if (!authStore.authInitialized) {
    await authStore.loadStoredAuth()
  }

  // Pages that don't require auth
  const publicPages = ['/login']

  // Redirect /register to /login (registration disabled)
  if (to.path === '/register') {
    return navigateTo('/login')
  }

  if (!authStore.isAuthenticated && !publicPages.includes(to.path)) {
    return navigateTo('/login')
  }

  // Redirect authenticated users away from auth pages
  if (authStore.isAuthenticated && publicPages.includes(to.path)) {
    return navigateTo('/')
  }
})

export default defineNuxtRouteMiddleware((to) => {
  const authStore = useAuthStore()

  // Pages that don't require auth
  const publicPages = ['/login', '/register']

  if (!authStore.isAuthenticated && !publicPages.includes(to.path)) {
    return navigateTo('/login')
  }

  // Redirect authenticated users away from auth pages
  if (authStore.isAuthenticated && publicPages.includes(to.path)) {
    return navigateTo('/')
  }
})

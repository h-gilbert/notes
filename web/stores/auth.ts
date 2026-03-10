import { defineStore } from 'pinia'
import type { User } from '~/types'
import { api } from '~/utils/api'

// Refresh token 5 minutes before expiry
const TOKEN_REFRESH_BUFFER = 5 * 60 * 1000 // 5 minutes in ms

// Cookie options for security
const getCookieOptions = () => {
  const isProduction = process.env.NODE_ENV === 'production'
  return {
    maxAge: 60 * 60 * 24 * 7, // 7 days
    secure: isProduction, // Only send over HTTPS in production
    sameSite: 'strict' as const, // Prevent CSRF
    path: '/'
  }
}

export const useAuthStore = defineStore('auth', () => {
  // Define cookie refs at setup level (correct context for useCookie)
  // This ensures maxAge and other options are properly applied
  const cookieOptions = getCookieOptions()
  const accessTokenCookie = useCookie<string | null>('auth_access_token', cookieOptions)
  const refreshTokenCookie = useCookie<string | null>('auth_refresh_token', cookieOptions)
  const userCookie = useCookie<string | null>('auth_user', cookieOptions)

  // State
  const user = ref<User | null>(null)
  const accessToken = ref<string | null>(null)
  const refreshToken = ref<string | null>(null)
  const expiresAt = ref<number | null>(null)
  const isLoading = ref(false)
  const refreshTimer = ref<ReturnType<typeof setTimeout> | null>(null)
  const isRefreshing = ref(false)
  const authInitialized = ref(false)
  const isRestoringAuth = ref(false)
  let refreshPromise: Promise<void> | null = null
  let restoreAuthPromise: Promise<void> | null = null

  // Getters
  const isAuthenticated = computed(() => !!accessToken.value)
  const token = computed(() => accessToken.value)

  // Helper functions
  function getTokenExpirationTimestamp(token: string): number | null {
    try {
      const parts = token.split('.')
      if (parts.length !== 3) return null

      let payload = parts[1]
      payload = payload.replace(/-/g, '+').replace(/_/g, '/')
      const padding = payload.length % 4
      if (padding) {
        payload += '='.repeat(4 - padding)
      }

      const decoded = JSON.parse(atob(payload))
      if (!decoded.exp) return null

      return decoded.exp * 1000
    } catch {
      return null
    }
  }

  function isTokenExpired(token: string): boolean {
    const expTimestamp = getTokenExpirationTimestamp(token)
    if (!expTimestamp) return true
    return expTimestamp < Date.now()
  }

  function cancelScheduledRefresh() {
    if (refreshTimer.value) {
      clearTimeout(refreshTimer.value)
      refreshTimer.value = null
    }
  }

  function setAuthData(newAccessToken: string, newRefreshToken: string, expiresIn: number, userData: User) {
    accessToken.value = newAccessToken
    refreshToken.value = newRefreshToken
    expiresAt.value = Date.now() + (expiresIn * 1000)
    user.value = userData

    // Write to cookies using the refs defined at setup level
    // This ensures cookie options (including maxAge) are properly applied
    accessTokenCookie.value = newAccessToken
    refreshTokenCookie.value = newRefreshToken
    userCookie.value = JSON.stringify(userData)

    api.setToken(newAccessToken)
  }

  function scheduleTokenRefresh() {
    cancelScheduledRefresh()

    if (!expiresAt.value) return

    // Calculate when to refresh (5 minutes before expiry)
    const refreshTime = expiresAt.value - Date.now() - TOKEN_REFRESH_BUFFER

    if (refreshTime <= 0) {
      // Token already expired or about to expire, refresh now
      doRefreshToken()
      return
    }

    // Schedule refresh
    refreshTimer.value = setTimeout(() => {
      doRefreshToken()
    }, refreshTime)
  }

  function clearAuthState(clearCookies = false) {
    cancelScheduledRefresh()
    accessToken.value = null
    refreshToken.value = null
    expiresAt.value = null
    user.value = null
    isRefreshing.value = false

    api.setToken(null)

    if (clearCookies) {
      accessTokenCookie.value = null
      refreshTokenCookie.value = null
      userCookie.value = null
    }
  }

  async function doRefreshToken() {
    if (refreshPromise) {
      return refreshPromise
    }

    refreshPromise = (async () => {
      if (!refreshToken.value) {
        logout()
        return
      }

      isRefreshing.value = true
      try {
        const response = await api.refreshToken(refreshToken.value)
        setAuthData(response.access_token, response.refresh_token, response.expires_in, response.user)
        scheduleTokenRefresh()
      } catch {
        // Token refresh failed - logout user
        logout()
      } finally {
        isRefreshing.value = false
      }
    })()

    try {
      await refreshPromise
    } finally {
      refreshPromise = null
    }
  }

  function logout() {
    // Note: Don't reset authInitialized here - it should only be set once per app lifecycle
    clearAuthState(true)
  }

  // Called during app init to hydrate state from cookies
  async function loadStoredAuth() {
    if (authInitialized.value) {
      return
    }

    if (restoreAuthPromise) {
      return restoreAuthPromise
    }

    restoreAuthPromise = (async () => {
      isRestoringAuth.value = true

      try {
        if (!refreshTokenCookie.value) {
          clearAuthState()
          return
        }

        refreshToken.value = refreshTokenCookie.value

        if (userCookie.value) {
          try {
            user.value = JSON.parse(userCookie.value)
          } catch {
            user.value = null
            userCookie.value = null
          }
        }

        if (accessTokenCookie.value && !isTokenExpired(accessTokenCookie.value)) {
          accessToken.value = accessTokenCookie.value
          expiresAt.value = getTokenExpirationTimestamp(accessTokenCookie.value)
          api.setToken(accessTokenCookie.value)
          scheduleTokenRefresh()
          return
        }

        await doRefreshToken()
      } finally {
        authInitialized.value = true
        isRestoringAuth.value = false
      }
    })()

    try {
      await restoreAuthPromise
    } finally {
      restoreAuthPromise = null
    }
  }

  async function login(username: string, password: string) {
    isLoading.value = true
    try {
      const response = await api.login({ username, password })
      setAuthData(response.access_token, response.refresh_token, response.expires_in, response.user)
      scheduleTokenRefresh()
    } finally {
      isLoading.value = false
    }
  }

  async function register(username: string, password: string) {
    isLoading.value = true
    try {
      const response = await api.register({ username, password })
      setAuthData(response.access_token, response.refresh_token, response.expires_in, response.user)
      scheduleTokenRefresh()
    } finally {
      isLoading.value = false
    }
  }

  async function changePassword(currentPassword: string, newPassword: string) {
    isLoading.value = true
    try {
      await api.changePassword({ current_password: currentPassword, new_password: newPassword })
    } finally {
      isLoading.value = false
    }
  }

  return {
    // State
    user,
    accessToken,
    refreshToken,
    expiresAt,
    isLoading,
    refreshTimer,
    isRefreshing,
    authInitialized,
    isRestoringAuth,
    // Getters
    isAuthenticated,
    token,
    // Actions
    login,
    register,
    changePassword,
    logout,
    loadStoredAuth,
    doRefreshToken,
    setAuthData,
    scheduleTokenRefresh,
    cancelScheduledRefresh,
    getTokenExpirationTimestamp,
    isTokenExpired
  }
})

import { defineStore } from 'pinia'
import type { User } from '~/types'
import { api } from '~/utils/api'

interface AuthState {
  user: User | null
  accessToken: string | null
  refreshToken: string | null
  expiresAt: number | null // timestamp when access token expires
  isLoading: boolean
  refreshTimer: ReturnType<typeof setTimeout> | null
}

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

export const useAuthStore = defineStore('auth', {
  state: (): AuthState => ({
    user: null,
    accessToken: null,
    refreshToken: null,
    expiresAt: null,
    isLoading: false,
    refreshTimer: null
  }),

  getters: {
    isAuthenticated: (state) => !!state.accessToken
  },

  actions: {
    async login(username: string, password: string) {
      this.isLoading = true
      try {
        const response = await api.login({ username, password })
        this.setAuthData(response.access_token, response.refresh_token, response.expires_in, response.user)
        this.scheduleTokenRefresh()
      } finally {
        this.isLoading = false
      }
    },

    async register(username: string, password: string) {
      this.isLoading = true
      try {
        const response = await api.register({ username, password })
        this.setAuthData(response.access_token, response.refresh_token, response.expires_in, response.user)
        this.scheduleTokenRefresh()
      } finally {
        this.isLoading = false
      }
    },

    async changePassword(currentPassword: string, newPassword: string) {
      this.isLoading = true
      try {
        await api.changePassword({ current_password: currentPassword, new_password: newPassword })
      } finally {
        this.isLoading = false
      }
    },

    logout() {
      this.cancelScheduledRefresh()
      this.accessToken = null
      this.refreshToken = null
      this.expiresAt = null
      this.user = null

      // Clear cookies with same options
      const cookieOptions = getCookieOptions()
      const accessTokenCookie = useCookie('auth_access_token', cookieOptions)
      const refreshTokenCookie = useCookie('auth_refresh_token', cookieOptions)
      const userCookie = useCookie('auth_user', cookieOptions)
      accessTokenCookie.value = null
      refreshTokenCookie.value = null
      userCookie.value = null

      api.setToken(null)
    },

    // Called during app init to hydrate state from cookies
    loadStoredAuth() {
      const cookieOptions = getCookieOptions()
      const accessTokenCookie = useCookie<string | null>('auth_access_token', cookieOptions)
      const refreshTokenCookie = useCookie<string | null>('auth_refresh_token', cookieOptions)
      const userCookie = useCookie<string | null>('auth_user', cookieOptions)

      // If we have a refresh token, we can try to restore the session
      if (refreshTokenCookie.value) {
        this.refreshToken = refreshTokenCookie.value

        if (userCookie.value) {
          try {
            this.user = JSON.parse(userCookie.value)
          } catch {
            userCookie.value = null
          }
        }

        // Check if access token is still valid
        if (accessTokenCookie.value && !this.isTokenExpired(accessTokenCookie.value)) {
          this.accessToken = accessTokenCookie.value
          this.expiresAt = this.getTokenExpirationTimestamp(accessTokenCookie.value)
          api.setToken(accessTokenCookie.value)
          this.scheduleTokenRefresh()
        } else {
          // Access token expired or missing, try to refresh
          this.doRefreshToken()
        }
      }
    },

    async doRefreshToken() {
      if (!this.refreshToken) {
        this.logout()
        return
      }

      try {
        const response = await api.refreshToken(this.refreshToken)
        this.setAuthData(response.access_token, response.refresh_token, response.expires_in, response.user)
        this.scheduleTokenRefresh()
      } catch (error) {
        console.error('Failed to refresh token:', error)
        this.logout()
      }
    },

    setAuthData(accessToken: string, refreshToken: string, expiresIn: number, user: User) {
      this.accessToken = accessToken
      this.refreshToken = refreshToken
      this.expiresAt = Date.now() + (expiresIn * 1000)
      this.user = user

      // Persist to cookies with security options
      const cookieOptions = getCookieOptions()
      const accessTokenCookie = useCookie('auth_access_token', cookieOptions)
      const refreshTokenCookie = useCookie('auth_refresh_token', cookieOptions)
      const userCookie = useCookie('auth_user', cookieOptions)

      accessTokenCookie.value = accessToken
      refreshTokenCookie.value = refreshToken
      userCookie.value = JSON.stringify(user)

      api.setToken(accessToken)
    },

    scheduleTokenRefresh() {
      this.cancelScheduledRefresh()

      if (!this.expiresAt) return

      // Calculate when to refresh (5 minutes before expiry)
      const refreshTime = this.expiresAt - Date.now() - TOKEN_REFRESH_BUFFER

      if (refreshTime <= 0) {
        // Token already expired or about to expire, refresh now
        this.doRefreshToken()
        return
      }

      // Schedule refresh
      this.refreshTimer = setTimeout(() => {
        this.doRefreshToken()
      }, refreshTime)
    },

    cancelScheduledRefresh() {
      if (this.refreshTimer) {
        clearTimeout(this.refreshTimer)
        this.refreshTimer = null
      }
    },

    // Parse JWT and get expiration timestamp
    getTokenExpirationTimestamp(token: string): number | null {
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
    },

    isTokenExpired(token: string): boolean {
      const expTimestamp = this.getTokenExpirationTimestamp(token)
      if (!expTimestamp) return true
      return expTimestamp < Date.now()
    }
  }
})

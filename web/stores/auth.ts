import { defineStore } from 'pinia'
import type { User } from '~/types'
import { api } from '~/utils/api'

interface AuthState {
  user: User | null
  token: string | null
  isLoading: boolean
  refreshTimer: ReturnType<typeof setInterval> | null
}

// Token refresh threshold: refresh if expiring in less than 24 hours
const TOKEN_REFRESH_THRESHOLD = 24 * 60 * 60 * 1000 // 24 hours in ms

export const useAuthStore = defineStore('auth', {
  state: (): AuthState => ({
    user: null,
    token: null,
    isLoading: false,
    refreshTimer: null
  }),

  getters: {
    isAuthenticated: (state) => !!state.token
  },

  actions: {
    async login(username: string, password: string) {
      this.isLoading = true
      try {
        const response = await api.login({ username, password })
        this.setAuthData(response.token, response.user)
        this.startTokenRefreshTimer()
      } finally {
        this.isLoading = false
      }
    },

    async register(username: string, password: string) {
      this.isLoading = true
      try {
        const response = await api.register({ username, password })
        this.setAuthData(response.token, response.user)
        this.startTokenRefreshTimer()
      } finally {
        this.isLoading = false
      }
    },

    logout() {
      this.stopTokenRefreshTimer()
      this.token = null
      this.user = null

      // Clear cookies
      const tokenCookie = useCookie('auth_token')
      const userCookie = useCookie('auth_user')
      tokenCookie.value = null
      userCookie.value = null

      api.setToken(null)
    },

    // Called during app init to hydrate state from cookies
    loadStoredAuth() {
      const tokenCookie = useCookie<string | null>('auth_token')
      const userCookie = useCookie<string | null>('auth_user')

      if (tokenCookie.value) {
        // Check if token is expired
        if (this.isTokenExpired(tokenCookie.value)) {
          console.log('Token expired, logging out')
          this.logout()
          return
        }

        this.token = tokenCookie.value
        api.setToken(tokenCookie.value)

        if (userCookie.value) {
          try {
            this.user = JSON.parse(userCookie.value)
          } catch {
            // Invalid user data, clear it
            userCookie.value = null
          }
        }

        // Check if token needs refresh
        if (this.shouldRefreshToken(tokenCookie.value)) {
          console.log('Token expiring soon, refreshing...')
          this.refreshToken()
        }

        // Start periodic refresh timer
        this.startTokenRefreshTimer()
      }
    },

    async refreshToken() {
      if (!this.token) return

      try {
        const response = await api.refreshToken()
        this.setAuthData(response.token, response.user)
        console.log('Token refreshed successfully')
      } catch (error) {
        console.error('Failed to refresh token:', error)
        // If refresh fails, log out the user
        this.logout()
      }
    },

    setAuthData(token: string, user: User) {
      this.token = token
      this.user = user

      // Persist to cookies (SSR-safe)
      const tokenCookie = useCookie('auth_token', { maxAge: 60 * 60 * 24 * 7 })
      const userCookie = useCookie('auth_user', { maxAge: 60 * 60 * 24 * 7 })
      tokenCookie.value = token
      userCookie.value = JSON.stringify(user)

      api.setToken(token)
    },

    startTokenRefreshTimer() {
      this.stopTokenRefreshTimer()
      // Check every hour if token needs refresh
      this.refreshTimer = setInterval(() => {
        if (this.token && this.shouldRefreshToken(this.token)) {
          this.refreshToken()
        }
      }, 60 * 60 * 1000) // 1 hour
    },

    stopTokenRefreshTimer() {
      if (this.refreshTimer) {
        clearInterval(this.refreshTimer)
        this.refreshTimer = null
      }
    },

    // Parse JWT and get expiration date
    getTokenExpirationDate(token: string): Date | null {
      try {
        const parts = token.split('.')
        if (parts.length !== 3) return null

        // Decode base64url payload
        let payload = parts[1]
        payload = payload.replace(/-/g, '+').replace(/_/g, '/')
        const padding = payload.length % 4
        if (padding) {
          payload += '='.repeat(4 - padding)
        }

        const decoded = JSON.parse(atob(payload))
        if (!decoded.exp) return null

        return new Date(decoded.exp * 1000)
      } catch {
        return null
      }
    },

    isTokenExpired(token: string): boolean {
      const expDate = this.getTokenExpirationDate(token)
      if (!expDate) return true
      return expDate < new Date()
    },

    shouldRefreshToken(token: string): boolean {
      const expDate = this.getTokenExpirationDate(token)
      if (!expDate) return true
      const timeUntilExpiry = expDate.getTime() - Date.now()
      return timeUntilExpiry < TOKEN_REFRESH_THRESHOLD
    }
  }
})

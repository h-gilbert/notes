import { defineStore } from 'pinia'
import type { User } from '~/types'
import { api } from '~/utils/api'

interface AuthState {
  user: User | null
  token: string | null
  isLoading: boolean
}

export const useAuthStore = defineStore('auth', {
  state: (): AuthState => ({
    user: null,
    token: null,
    isLoading: false
  }),

  getters: {
    isAuthenticated: (state) => !!state.token
  },

  actions: {
    async login(username: string, password: string) {
      this.isLoading = true
      try {
        const response = await api.login({ username, password })
        this.token = response.token
        this.user = response.user

        // Persist to cookies (SSR-safe)
        const tokenCookie = useCookie('auth_token', { maxAge: 60 * 60 * 24 * 7 })
        const userCookie = useCookie('auth_user', { maxAge: 60 * 60 * 24 * 7 })
        tokenCookie.value = response.token
        userCookie.value = JSON.stringify(response.user)

        api.setToken(response.token)
      } finally {
        this.isLoading = false
      }
    },

    async register(username: string, password: string) {
      this.isLoading = true
      try {
        const response = await api.register({ username, password })
        this.token = response.token
        this.user = response.user

        // Persist to cookies (SSR-safe)
        const tokenCookie = useCookie('auth_token', { maxAge: 60 * 60 * 24 * 7 })
        const userCookie = useCookie('auth_user', { maxAge: 60 * 60 * 24 * 7 })
        tokenCookie.value = response.token
        userCookie.value = JSON.stringify(response.user)

        api.setToken(response.token)
      } finally {
        this.isLoading = false
      }
    },

    logout() {
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
      }
    }
  }
})

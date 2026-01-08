import type { AuthRequest, AuthResponse, NoteDTO, RefreshRequest, SyncRequest, SyncResponse, User } from '~/types'

class ApiClient {
  private baseUrl: string = ''
  private token: string | null = null

  configure(baseUrl: string) {
    this.baseUrl = baseUrl
  }

  setToken(token: string | null) {
    this.token = token
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown
  ): Promise<T> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    }

    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`
    }

    const response = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined
    })

    if (response.status === 401) {
      throw new Error('Unauthorized')
    }

    if (!response.ok) {
      const errorText = await response.text()
      throw new Error(errorText || `HTTP ${response.status}`)
    }

    if (response.status === 204) {
      return {} as T
    }

    return response.json()
  }

  // Auth
  async register(data: AuthRequest): Promise<AuthResponse> {
    return this.request('POST', '/api/auth/register', data)
  }

  async login(data: AuthRequest): Promise<AuthResponse> {
    return this.request('POST', '/api/auth/login', data)
  }

  async me(): Promise<User> {
    return this.request('GET', '/api/auth/me')
  }

  async refreshToken(refreshToken: string): Promise<AuthResponse> {
    return this.request('POST', '/api/auth/refresh', { refresh_token: refreshToken } as RefreshRequest)
  }

  // Notes
  async fetchNotes(since?: string): Promise<SyncResponse> {
    const query = since ? `?since=${encodeURIComponent(since)}` : ''
    return this.request('GET', `/api/notes${query}`)
  }

  async createNote(note: NoteDTO): Promise<NoteDTO> {
    return this.request('POST', '/api/notes', note)
  }

  async updateNote(note: NoteDTO): Promise<NoteDTO> {
    return this.request('PUT', `/api/notes/${note.id}`, note)
  }

  async deleteNote(id: string): Promise<void> {
    return this.request('DELETE', `/api/notes/${id}`)
  }

  async syncNotes(data: SyncRequest): Promise<SyncResponse> {
    return this.request('POST', '/api/notes/sync', data)
  }
}

export const api = new ApiClient()

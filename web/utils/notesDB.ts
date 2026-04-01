import { toRaw } from 'vue'
import type { Note } from '~/types'

const DB_NAME = 'notes-app'
const DB_VERSION = 1
const NOTES_STORE = 'notes'
const META_STORE = 'meta'

class NotesDB {
  private db: IDBDatabase | null = null

  async open(): Promise<IDBDatabase> {
    if (this.db) return this.db

    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION)

      request.onupgradeneeded = () => {
        const db = request.result
        if (!db.objectStoreNames.contains(NOTES_STORE)) {
          db.createObjectStore(NOTES_STORE, { keyPath: 'id' })
        }
        if (!db.objectStoreNames.contains(META_STORE)) {
          db.createObjectStore(META_STORE, { keyPath: 'key' })
        }
      }

      request.onsuccess = () => {
        this.db = request.result
        resolve(this.db)
      }

      request.onerror = () => {
        reject(request.error)
      }
    })
  }

  private async getDB(): Promise<IDBDatabase> {
    if (this.db) return this.db
    return this.open()
  }

  async getAllNotes(): Promise<Note[]> {
    const db = await this.getDB()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(NOTES_STORE, 'readonly')
      const store = tx.objectStore(NOTES_STORE)
      const request = store.getAll()
      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    })
  }

  async putNote(note: Note): Promise<void> {
    const db = await this.getDB()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(NOTES_STORE, 'readwrite')
      const store = tx.objectStore(NOTES_STORE)
      store.put(JSON.parse(JSON.stringify(toRaw(note))))
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
    })
  }

  async putAllNotes(notes: Note[]): Promise<void> {
    const db = await this.getDB()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(NOTES_STORE, 'readwrite')
      const store = tx.objectStore(NOTES_STORE)
      store.clear()
      for (const note of notes) {
        store.put(JSON.parse(JSON.stringify(toRaw(note))))
      }
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
    })
  }

  async deleteNote(id: string): Promise<void> {
    const db = await this.getDB()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(NOTES_STORE, 'readwrite')
      const store = tx.objectStore(NOTES_STORE)
      store.delete(id)
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
    })
  }

  async clearNotes(): Promise<void> {
    try {
      const db = await this.getDB()
      return new Promise((resolve, reject) => {
        const tx = db.transaction([NOTES_STORE, META_STORE], 'readwrite')
        tx.objectStore(NOTES_STORE).clear()
        tx.objectStore(META_STORE).clear()
        tx.oncomplete = () => resolve()
        tx.onerror = () => reject(tx.error)
      })
    } catch {
      // DB may not be open yet (e.g. logout before any notes loaded)
    }
  }

  async getMeta(key: string): Promise<any> {
    const db = await this.getDB()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(META_STORE, 'readonly')
      const store = tx.objectStore(META_STORE)
      const request = store.get(key)
      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    })
  }

  async setMeta(key: string, value: any): Promise<void> {
    const db = await this.getDB()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(META_STORE, 'readwrite')
      const store = tx.objectStore(META_STORE)
      store.put({ key, value })
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
    })
  }
}

export const notesDB = new NotesDB()

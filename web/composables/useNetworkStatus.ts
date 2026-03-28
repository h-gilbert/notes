const isOnline = ref(true)
let initialized = false

export function useNetworkStatus() {
  function setup() {
    if (initialized || typeof window === 'undefined') return
    initialized = true

    isOnline.value = navigator.onLine

    window.addEventListener('online', () => {
      isOnline.value = true
    })
    window.addEventListener('offline', () => {
      isOnline.value = false
    })
  }

  return {
    isOnline: readonly(isOnline),
    setup
  }
}

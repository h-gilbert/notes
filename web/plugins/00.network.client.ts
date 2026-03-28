export default defineNuxtPlugin(() => {
  const { setup } = useNetworkStatus()
  setup()
})

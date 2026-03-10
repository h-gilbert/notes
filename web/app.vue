<template>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
</template>

<script setup lang="ts">
// Initialize auth state - load user from cookie on both server and client
const authStore = useAuthStore()
await authStore.loadStoredAuth()
</script>

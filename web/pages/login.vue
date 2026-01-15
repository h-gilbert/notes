<template>
  <div>
    <NuxtLayout name="auth">
      <div class="login-card card">
        <h1 class="title">Welcome back</h1>
        <p class="subtitle">Sign in to your account</p>

        <form @submit.prevent="handleSubmit" class="form">
          <div class="field">
            <label for="username" class="label">Username</label>
            <input
              id="username"
              v-model="username"
              type="text"
              class="input"
              placeholder="Enter your username"
              required
            />
          </div>

          <div class="field">
            <label for="password" class="label">Password</label>
            <input
              id="password"
              v-model="password"
              type="password"
              class="input"
              placeholder="Enter your password"
              required
            />
          </div>

          <p v-if="error" class="error">{{ error }}</p>

          <button type="submit" class="btn btn-primary submit-btn" :disabled="isLoading">
            {{ isLoading ? 'Signing in...' : 'Sign in' }}
          </button>
        </form>

        <div class="divider">
          <span>or</span>
        </div>

        <button
          type="button"
          class="btn btn-secondary demo-btn"
          :disabled="isLoading"
          @click="loginAsDemo"
        >
          {{ isLoading ? 'Loading...' : 'Try Demo' }}
        </button>
      </div>
    </NuxtLayout>
  </div>
</template>

<script setup lang="ts">
definePageMeta({
  layout: false,
  middleware: 'auth'
})

const router = useRouter()
const authStore = useAuthStore()

const username = ref('')
const password = ref('')
const error = ref('')
const isLoading = ref(false)

const handleSubmit = async () => {
  error.value = ''
  isLoading.value = true

  try {
    await authStore.login(username.value, password.value)
    router.push('/')
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Login failed'
  } finally {
    isLoading.value = false
  }
}

const loginAsDemo = async () => {
  error.value = ''
  isLoading.value = true

  try {
    await authStore.login('demo', 'DemoPassword123!')
    router.push('/')
  } catch (e) {
    error.value = 'Demo login failed. Please try again.'
  } finally {
    isLoading.value = false
  }
}
</script>

<style scoped>
.login-card {
  padding: var(--spacing-xl);
}

.title {
  font-size: 28px;
  font-weight: 700;
  color: var(--color-text-primary);
  margin-bottom: var(--spacing-xs);
}

.subtitle {
  color: var(--color-text-secondary);
  margin-bottom: var(--spacing-lg);
}

.form {
  display: flex;
  flex-direction: column;
  gap: var(--spacing-md);
}

.field {
  display: flex;
  flex-direction: column;
  gap: var(--spacing-xs);
}

.label {
  font-size: 14px;
  font-weight: 500;
  color: var(--color-text-secondary);
}

.error {
  color: var(--color-danger);
  font-size: 14px;
}

.submit-btn {
  width: 100%;
  margin-top: var(--spacing-sm);
}

.divider {
  display: flex;
  align-items: center;
  margin: var(--spacing-lg) 0;
}

.divider::before,
.divider::after {
  content: '';
  flex: 1;
  border-bottom: 1px solid var(--color-border);
}

.divider span {
  padding: 0 var(--spacing-md);
  color: var(--color-text-secondary);
  font-size: 14px;
}

.demo-btn {
  width: 100%;
}
</style>

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

        <p class="footer">
          Don't have an account?
          <NuxtLink to="/register" class="link">Sign up</NuxtLink>
        </p>
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

.footer {
  margin-top: var(--spacing-lg);
  text-align: center;
  color: var(--color-text-secondary);
  font-size: 14px;
}

.link {
  color: var(--color-accent);
  font-weight: 500;
}

.link:hover {
  text-decoration: underline;
}
</style>

<template>
  <div>
    <NuxtLayout name="auth">
      <div class="register-card card">
        <h1 class="title">Create account</h1>
        <p class="subtitle">Sign up to get started</p>

        <form @submit.prevent="handleSubmit" class="form">
          <div class="field">
            <label for="username" class="label">Username</label>
            <input
              id="username"
              v-model="username"
              type="text"
              class="input"
              placeholder="Choose a username"
              required
              minlength="3"
            />
          </div>

          <div class="field">
            <label for="password" class="label">Password</label>
            <input
              id="password"
              v-model="password"
              type="password"
              class="input"
              placeholder="Choose a password"
              required
              minlength="6"
            />
          </div>

          <div class="field">
            <label for="confirmPassword" class="label">Confirm Password</label>
            <input
              id="confirmPassword"
              v-model="confirmPassword"
              type="password"
              class="input"
              placeholder="Confirm your password"
              required
            />
          </div>

          <p v-if="error" class="error">{{ error }}</p>

          <button type="submit" class="btn btn-primary submit-btn" :disabled="isLoading">
            {{ isLoading ? 'Creating account...' : 'Create account' }}
          </button>
        </form>

        <p class="footer">
          Already have an account?
          <NuxtLink to="/login" class="link">Sign in</NuxtLink>
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
const confirmPassword = ref('')
const error = ref('')
const isLoading = ref(false)

const handleSubmit = async () => {
  error.value = ''

  if (password.value !== confirmPassword.value) {
    error.value = 'Passwords do not match'
    return
  }

  isLoading.value = true

  try {
    await authStore.register(username.value, password.value)
    router.push('/')
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Registration failed'
  } finally {
    isLoading.value = false
  }
}
</script>

<style scoped>
.register-card {
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

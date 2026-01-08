<template>
  <div class="settings-container">
    <h1 class="page-title">Settings</h1>

    <section class="settings-section">
      <h2 class="section-title">Account</h2>
      <div class="card">
        <div class="account-info">
          <span class="label">Signed in as</span>
          <span class="value">{{ authStore.user?.username }}</span>
        </div>
      </div>
    </section>

    <section class="settings-section">
      <h2 class="section-title">Change Password</h2>
      <div class="card">
        <form @submit.prevent="handleChangePassword" class="form">
          <div class="field">
            <label for="currentPassword" class="label">Current Password</label>
            <input
              id="currentPassword"
              v-model="currentPassword"
              type="password"
              class="input"
              placeholder="Enter current password"
              required
            />
          </div>

          <div class="field">
            <label for="newPassword" class="label">New Password</label>
            <input
              id="newPassword"
              v-model="newPassword"
              type="password"
              class="input"
              placeholder="Enter new password"
              required
              minlength="6"
            />
            <span v-if="newPassword && newPassword.length < 6" class="field-error">
              Password must be at least 6 characters
            </span>
          </div>

          <div class="field">
            <label for="confirmPassword" class="label">Confirm New Password</label>
            <input
              id="confirmPassword"
              v-model="confirmPassword"
              type="password"
              class="input"
              placeholder="Confirm new password"
              required
            />
            <span v-if="confirmPassword && newPassword !== confirmPassword" class="field-error">
              Passwords do not match
            </span>
          </div>

          <p v-if="error" class="error">{{ error }}</p>
          <p v-if="success" class="success">{{ success }}</p>

          <button
            type="submit"
            class="btn btn-primary submit-btn"
            :disabled="!isFormValid || isLoading"
          >
            {{ isLoading ? 'Changing password...' : 'Change Password' }}
          </button>
        </form>
      </div>
    </section>

    <section class="settings-section">
      <h2 class="section-title">About</h2>
      <div class="card">
        <div class="about-info">
          <span class="label">Version</span>
          <span class="value">1.0.0</span>
        </div>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
definePageMeta({
  middleware: 'auth'
})

const authStore = useAuthStore()

const currentPassword = ref('')
const newPassword = ref('')
const confirmPassword = ref('')
const error = ref('')
const success = ref('')
const isLoading = ref(false)

const isFormValid = computed(() => {
  return (
    currentPassword.value.length > 0 &&
    newPassword.value.length >= 6 &&
    newPassword.value === confirmPassword.value
  )
})

const handleChangePassword = async () => {
  error.value = ''
  success.value = ''

  if (newPassword.value !== confirmPassword.value) {
    error.value = 'Passwords do not match'
    return
  }

  if (newPassword.value.length < 6) {
    error.value = 'New password must be at least 6 characters'
    return
  }

  isLoading.value = true

  try {
    await authStore.changePassword(currentPassword.value, newPassword.value)
    success.value = 'Password changed successfully'
    currentPassword.value = ''
    newPassword.value = ''
    confirmPassword.value = ''
  } catch (e) {
    if (e instanceof Error) {
      // Parse error message from API
      try {
        const errorData = JSON.parse(e.message)
        error.value = errorData.message || 'Failed to change password'
      } catch {
        error.value = e.message === 'Unauthorized' ? 'Current password is incorrect' : e.message
      }
    } else {
      error.value = 'Failed to change password'
    }
  } finally {
    isLoading.value = false
  }
}
</script>

<style scoped>
.settings-container {
  max-width: 600px;
  margin: 0 auto;
  padding: var(--spacing-lg);
}

.page-title {
  font-size: 28px;
  font-weight: 700;
  color: var(--color-text-primary);
  margin-bottom: var(--spacing-lg);
}

.settings-section {
  margin-bottom: var(--spacing-xl);
}

.section-title {
  font-size: 14px;
  font-weight: 600;
  color: var(--color-text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin-bottom: var(--spacing-sm);
}

.card {
  background-color: var(--color-surface);
  border-radius: var(--radius-medium);
  padding: var(--spacing-md);
  box-shadow: 0 1px 3px var(--color-shadow-light);
}

.account-info,
.about-info {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.label {
  font-size: 14px;
  font-weight: 500;
  color: var(--color-text-secondary);
}

.value {
  font-size: 14px;
  color: var(--color-text-primary);
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

.field-error {
  font-size: 12px;
  color: var(--color-warning);
}

.error {
  color: var(--color-danger);
  font-size: 14px;
  padding: var(--spacing-sm);
  background-color: rgba(239, 68, 68, 0.1);
  border-radius: var(--radius-small);
}

.success {
  color: var(--color-success);
  font-size: 14px;
  padding: var(--spacing-sm);
  background-color: rgba(34, 197, 94, 0.1);
  border-radius: var(--radius-small);
}

.submit-btn {
  width: 100%;
  margin-top: var(--spacing-sm);
}

.submit-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
</style>

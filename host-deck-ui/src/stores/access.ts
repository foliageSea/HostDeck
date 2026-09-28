import { ref } from 'vue'
import { defineStore } from 'pinia'
import { accessApi } from '@/api/access'
import { setAccessUnauthorizedHandler } from '@/lib/http'

export const useAccessStore = defineStore('access', () => {
  const initialized = ref(false)
  const enabled = ref(false)
  const authenticated = ref(false)
  const passwordLoginEnabled = ref(false)
  const totpLoginEnabled = ref(false)
  const totpSource = ref<'none' | 'environment' | 'stored'>('none')

  async function initialize() {
    setAccessUnauthorizedHandler(() => {
      authenticated.value = false
    })

    try {
      const state = await accessApi.getState()
      enabled.value = state.enabled
      authenticated.value = state.authenticated
      passwordLoginEnabled.value = state.passwordLoginEnabled
      totpLoginEnabled.value = state.totpLoginEnabled
      totpSource.value = state.totpSource
    } finally {
      initialized.value = true
    }
  }

  async function login(credential: { password?: string; code?: string }) {
    await accessApi.login(credential)
    authenticated.value = true
  }

  async function logout() {
    await accessApi.logout()
    authenticated.value = false
  }

  return {
    authenticated,
    enabled,
    initialized,
    passwordLoginEnabled,
    totpLoginEnabled,
    totpSource,
    initialize,
    login,
    logout,
  }
})

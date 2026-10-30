import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { VueQueryPlugin } from '@tanstack/vue-query'
import { isAxiosError } from 'axios'
import App from './App.vue'
import StartupUnavailable from '@/components/common/StartupUnavailable.vue'
import { useSettingsStore } from '@/stores/settings'
import { useAccessStore } from '@/stores/access'
import './style.css'
import '@host-deck/webos/style.css'
import 'virtual:uno.css'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(VueQueryPlugin)

const settingsStore = useSettingsStore(pinia)
const accessStore = useAccessStore(pinia)
try {
  await accessStore.initialize()
  if (accessStore.authenticated) {
    await settingsStore.initialize()
  }

  app.mount('#app')
} catch (error) {
  if (isAxiosError(error) && !error.response) {
    createApp(StartupUnavailable).mount('#app')
  } else {
    throw error
  }
}

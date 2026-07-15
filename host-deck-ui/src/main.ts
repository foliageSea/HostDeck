import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { VueQueryPlugin } from '@tanstack/vue-query'
import App from './App.vue'
import router from './router'
import { useSettingsStore } from '@/stores/settings'
import { useAccessStore } from '@/stores/access'
import './style.css'
import 'virtual:uno.css'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)
app.use(VueQueryPlugin)

const settingsStore = useSettingsStore(pinia)
const accessStore = useAccessStore(pinia)
await accessStore.initialize()
if (accessStore.authenticated) {
  await settingsStore.initialize()
}

app.mount('#app')

import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { VueQueryPlugin } from '@tanstack/vue-query'
import App from './App.vue'
import { useSettingsStore } from '@/stores/settings'
import { useAccessStore } from '@/stores/access'
import './style.css'
import 'virtual:uno.css'

const suppressedNativeTitles = new WeakMap<Element, string>()

document.addEventListener(
  'mouseover',
  (event) => {
    const target = event.target instanceof Element ? event.target.closest('[title]') : null
    if (!target || suppressedNativeTitles.has(target)) return

    const title = target.getAttribute('title')
    if (title === null) return

    suppressedNativeTitles.set(target, title)
    target.removeAttribute('title')
    target.addEventListener(
      'mouseleave',
      () => {
        const suppressedTitle = suppressedNativeTitles.get(target)
        if (suppressedTitle === undefined) return

        target.setAttribute('title', suppressedTitle)
        suppressedNativeTitles.delete(target)
      },
      { once: true },
    )
  },
  true,
)

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(VueQueryPlugin)

const settingsStore = useSettingsStore(pinia)
const accessStore = useAccessStore(pinia)
await accessStore.initialize()
if (accessStore.authenticated) {
  await settingsStore.initialize()
}

app.mount('#app')

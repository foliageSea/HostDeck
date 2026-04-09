import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { VueQueryPlugin } from '@tanstack/vue-query'
import { createDiscreteApi, darkTheme, dateZhCN, zhCN } from 'naive-ui'
import App from './App.vue'
import router from './router'
import { installUiApi } from './lib/ui'
import './style.css'

const app = createApp(App)
const pinia = createPinia()

const { message, notification, dialog, loadingBar } = createDiscreteApi(
  ['message', 'notification', 'dialog', 'loadingBar'],
  {
    configProviderProps: {
      locale: zhCN,
      dateLocale: dateZhCN,
      theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? darkTheme : null,
    },
  },
)

installUiApi({ message, notification, dialog, loadingBar })

app.use(pinia)
app.use(router)
app.use(VueQueryPlugin)

app.mount('#app')

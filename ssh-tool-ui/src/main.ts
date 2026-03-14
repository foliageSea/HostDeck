import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import './style.css'
import { setupFetchInterceptor } from './lib/fetch-interceptor'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)

setupFetchInterceptor(pinia)

app.mount('#app')

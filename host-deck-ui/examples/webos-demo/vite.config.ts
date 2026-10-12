import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Intentionally no aliases, auto-imports, UnoCSS or HostDeck configuration.
export default defineConfig({ plugins: [vue()] })

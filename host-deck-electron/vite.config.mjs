import { readFileSync } from 'node:fs'
import { fileURLToPath, URL } from 'node:url'

import vue from '@vitejs/plugin-vue'
import { defineConfig, loadEnv } from 'vite'
import devTls from '../host-deck-ui/scripts/dev-tls.cjs'

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf-8'))

export default defineConfig(({ mode, command }) => ({
  base: './',
  appType: 'mpa',
  build: {
    emptyOutDir: true,
    outDir: 'dist',
    rollupOptions: {
      input: {
        loading: fileURLToPath(new URL('./src/renderer/loading.html', import.meta.url)),
        tabs: fileURLToPath(new URL('./src/renderer/tabs.html', import.meta.url)),
      },
    },
  },
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
  },
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src/renderer/src', import.meta.url)),
    },
  },
  server: {
    port: 5180,
    https:
      command === 'serve'
        ? devTls.readDevHttps(
            { ...loadEnv(mode, fileURLToPath(new URL('./', import.meta.url)), ''), ...process.env },
            fileURLToPath(new URL('../', import.meta.url)),
          )
        : undefined,
  },
}))

import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import UnoCSS from 'unocss/vite'
import AutoImport from 'unplugin-auto-import/vite'
import { NaiveUiResolver } from 'unplugin-vue-components/resolvers'
import Components from 'unplugin-vue-components/vite'
import { fileURLToPath, URL } from 'node:url'
import { readFileSync } from 'node:fs'

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf-8')) as {
  version: string
}

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const proxyTarget = env.VITE_DEV_PROXY_TARGET || 'http://localhost:8080'

  return {
    define: {
      __APP_VERSION__: JSON.stringify(pkg.version),
    },
    resolve: {
      alias: {
        '@': fileURLToPath(new URL('./src', import.meta.url)),
      },
    },
    server: {
      port: 5178,
      proxy: {
        '/api': {
          target: proxyTarget,
          changeOrigin: false,
          ws: true,
        },
        '/wallpapers': {
          target: proxyTarget,
          changeOrigin: false,
        },
        '/api/ws/terminal': {
          target: proxyTarget,
          changeOrigin: false,
          ws: true,
        },
      },
    },
    plugins: [
      vue(),
      UnoCSS({
        configFile: fileURLToPath(new URL('./uno.config.ts', import.meta.url)),
      }),
      AutoImport({
        imports: [
          'vue',
          {
            'naive-ui': ['useDialog', 'useMessage', 'useNotification', 'useLoadingBar'],
          },
        ],
      }),
      Components({
        resolvers: [
          {
            type: 'component',
            resolve: (name: string) =>
              name === 'NButton'
                ? { name: 'default', from: '@/components/common/RoundedButton.vue' }
                : undefined,
          },
          NaiveUiResolver(),
        ],
      }),
    ],
  }
})

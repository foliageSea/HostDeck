import { defineConfig, loadEnv } from 'vite'
import type { Plugin } from 'vite'
import vue from '@vitejs/plugin-vue'
import UnoCSS from 'unocss/vite'
import AutoImport from 'unplugin-auto-import/vite'
import { NaiveUiResolver } from 'unplugin-vue-components/resolvers'
import Components from 'unplugin-vue-components/vite'
import { fileURLToPath, URL } from 'node:url'
import { cpSync, mkdirSync, readFileSync } from 'node:fs'

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf-8')) as {
  version: string
}

function legalFilesPlugin(): Plugin {
  const repoRoot = new URL('../', import.meta.url)
  const outputRoot = new URL('./dist/licenses/', import.meta.url)
  const legalFiles = new Map([
    ['/licenses/GPL-3.0.txt', new URL('LICENSE', repoRoot)],
    ['/licenses/THIRD_PARTY_NOTICES.txt', new URL('THIRD_PARTY_NOTICES.md', repoRoot)],
  ])
  let isBuild = false

  return {
    name: 'hostdeck-legal-files',
    configResolved(config) {
      isBuild = config.command === 'build'
    },
    configureServer(server) {
      server.middlewares.use((request, response, next) => {
        const source = legalFiles.get(request.url?.split('?')[0] ?? '')
        if (!source) {
          next()
          return
        }

        response.setHeader('Content-Type', 'text/plain; charset=utf-8')
        response.end(readFileSync(source))
      })
    },
    closeBundle() {
      if (!isBuild) {
        return
      }

      mkdirSync(outputRoot, { recursive: true })
      cpSync(new URL('LICENSE', repoRoot), new URL('GPL-3.0.txt', outputRoot))
      cpSync(new URL('THIRD_PARTY_NOTICES.md', repoRoot), new URL('THIRD_PARTY_NOTICES.txt', outputRoot))
      cpSync(new URL('./src/assets/MapleMono-OFL.txt', import.meta.url), new URL('MapleMono-OFL.txt', outputRoot))
      cpSync(
        new URL('./src/assets/app-icons/mac-tahoe/', import.meta.url),
        new URL('mac-tahoe/source/app-icons/', outputRoot),
        { recursive: true },
      )
      cpSync(
        new URL('./src/assets/file-icons/mac-tahoe/', import.meta.url),
        new URL('mac-tahoe/source/file-icons/', outputRoot),
        { recursive: true },
      )
    },
  }
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
      legalFilesPlugin(),
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

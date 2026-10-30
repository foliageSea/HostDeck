import { defineConfig, loadEnv } from 'vite'
import type { Plugin } from 'vite'
import vue from '@vitejs/plugin-vue'
import UnoCSS from 'unocss/vite'
import AutoImport from 'unplugin-auto-import/vite'
import { NaiveUiResolver } from 'unplugin-vue-components/resolvers'
import Components from 'unplugin-vue-components/vite'
import { fileURLToPath, URL } from 'node:url'
import { cpSync, mkdirSync, readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { resolve } from 'node:path'

const { readDevHttps, readDevProxy } = createRequire(import.meta.url)('./scripts/dev-tls.cjs')
const repoRootPath = fileURLToPath(new URL('../', import.meta.url))

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf-8')) as {
  version: string
}

const macTahoeSourceGroups = [
  {
    sourceDir: './src/assets/mac-tahoe/src/apps/scalable/',
    outputDir: 'mac-tahoe/source/app-icons/',
    files: [
      'accessories-text-editor.svg',
      'application-default-icon.svg',
      'docker.svg',
      'eog.svg',
      'evolution-tasks.svg',
      'file-manager.svg',
      'gpk-log.svg',
      'junction.svg',
      'log-out.svg',
      'logview.svg',
      'multitasking-view.svg',
      'preferences-system.svg',
      'stacks-task-manager.svg',
      'terminal.svg',
      'utilities-system-monitor.svg',
      'web-browser.svg',
    ],
  },
  {
    sourceDir: './src/assets/mac-tahoe/src/apps/22/',
    outputDir: 'mac-tahoe/source/app-icons/',
    files: ['network-connect.svg'],
  },
  {
    sourceDir: './src/assets/mac-tahoe/src/mimes/scalable/',
    outputDir: 'mac-tahoe/source/file-icons/',
    files: [
      'application-blank.svg',
      'application-certificate.svg',
      'application-json.svg',
      'application-pdf.svg',
      'application-script-blank.svg',
      'application-sql.svg',
      'application-toml.svg',
      'application-x-archive.svg',
      'application-x-pem-key.svg',
      'application-x-shellscript.svg',
      'audio-x-generic.svg',
      'image-x-generic.svg',
      'text-css.svg',
      'text-html.svg',
      'text-markdown.svg',
      'text-rust.svg',
      'text-x-generic.svg',
      'text-x-java.svg',
      'text-x-javascript.svg',
      'text-x-python.svg',
      'text-x-typescript.svg',
      'text-xml.svg',
      'text-yaml.svg',
      'video-x-generic.svg',
      'x-office-document.svg',
      'x-office-presentation.svg',
      'x-office-spreadsheet.svg',
    ],
  },
  {
    sourceDir: './src/assets/mac-tahoe/src/places/scalable/',
    outputDir: 'mac-tahoe/source/file-icons/',
    files: ['folder.svg'],
  },
]

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
      cpSync(
        new URL('THIRD_PARTY_NOTICES.md', repoRoot),
        new URL('THIRD_PARTY_NOTICES.txt', outputRoot),
      )
      cpSync(
        new URL('./src/assets/MapleMono-OFL.txt', import.meta.url),
        new URL('MapleMono-OFL.txt', outputRoot),
      )
      cpSync(
        new URL('./src/assets/mac-tahoe/AUTHORS', import.meta.url),
        new URL('mac-tahoe/AUTHORS', outputRoot),
      )
      cpSync(
        new URL('./src/assets/mac-tahoe/COPYING', import.meta.url),
        new URL('mac-tahoe/COPYING', outputRoot),
      )
      cpSync(
        new URL('./src/assets/mac-tahoe/README.md', import.meta.url),
        new URL('mac-tahoe/README.md', outputRoot),
      )

      for (const group of macTahoeSourceGroups) {
        const sourceDir = new URL(group.sourceDir, import.meta.url)
        const targetDir = new URL(group.outputDir, outputRoot)
        mkdirSync(targetDir, { recursive: true })

        for (const file of group.files) {
          cpSync(new URL(file, sourceDir), new URL(file, targetDir))
        }
      }
    },
  }
}

// https://vite.dev/config/
export default defineConfig(({ mode, command }) => {
  const env = {
    ...loadEnv(mode, fileURLToPath(new URL('./', import.meta.url)), ''),
    ...process.env,
  }
  const https = command === 'serve' ? readDevHttps(env, repoRootPath) : undefined
  const proxy = command === 'serve' ? readDevProxy(env, repoRootPath) : {}
  const proxyTarget = proxy.target

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
      https,
      port: 5178,
      watch: {
        ignored: ['**/src/assets/mac-tahoe/**'],
      },
      proxy: {
        '/api': {
          target: proxyTarget,
          agent: proxy.agent,
          changeOrigin: false,
          ws: true,
        },
        '/ide': {
          target: proxyTarget,
          agent: proxy.agent,
          changeOrigin: false,
          ws: true,
        },
        '/port-forward': {
          target: proxyTarget,
          agent: proxy.agent,
          changeOrigin: false,
          ws: true,
        },
        '/wallpapers': {
          target: proxyTarget,
          agent: proxy.agent,
          changeOrigin: false,
        },
        '/api/ws/terminal': {
          target: proxyTarget,
          agent: proxy.agent,
          changeOrigin: false,
          ws: true,
        },
      },
    },
    plugins: [
      {
        name: 'hostdeck-dev-backend',
        configureServer(server) {
          const readyFile = env.HOSTDECK_DEV_BACKEND_READY_FILE
          if (!readyFile) return
          const absolute = resolve(repoRootPath, readyFile)
          let previous = readFileSync(absolute, 'utf8')
          server.watcher.add(absolute)
          const restart = (file: string) => {
            if (file !== absolute) return
            try {
              const next = readFileSync(absolute, 'utf8')
              JSON.parse(next)
              if (next === previous) return
              previous = next
              void server.restart().catch((error) => server.config.logger.error(String(error)))
            } catch {
              // The backend may still be writing the ready file.
            }
          }
          server.watcher.on('add', restart).on('change', restart)
          server.httpServer?.once('close', () => {
            server.watcher.off('add', restart).off('change', restart)
            proxy.agent?.destroy()
          })
        },
      },
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

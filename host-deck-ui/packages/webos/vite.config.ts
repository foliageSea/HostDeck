import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import UnoCSS from 'unocss/vite'
import { presetUno } from 'unocss'

const scopedPreset = presetUno()
scopedPreset.preflights = scopedPreset.preflights?.map((preflight) => ({
  ...preflight,
  getCSS: async (context) =>
    (await preflight.getCSS(context))
      ?.replaceAll(
        '*,::before,::after',
        '.webos-root,.webos-root *,.webos-root ::before,.webos-root ::after',
      )
      .replaceAll('::backdrop{', '.webos-root::backdrop{'),
}))

export default defineConfig({
  plugins: [
    vue(),
    UnoCSS({
      configFile: false,
      presets: [scopedPreset],
      postprocess: (utility) => {
        utility.selector = `.webos-root ${utility.selector}`
      },
    }),
  ],
  build: {
    lib: {
      entry: fileURLToPath(new URL('./src/index.ts', import.meta.url)),
      formats: ['es'],
      fileName: 'webos',
      cssFileName: 'webos',
    },
    rolldownOptions: {
      external: ['vue', 'naive-ui', '@lucide/vue'],
    },
  },
})

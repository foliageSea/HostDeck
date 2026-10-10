import { build } from 'esbuild'

await build({
  entryPoints: ['src/bridge.mjs'],
  outfile: 'dist/bridge.mjs',
  bundle: true,
  external: ['@earendil-works/pi-ai', '@earendil-works/pi-ai/*'],
  platform: 'node',
  target: 'node22',
  format: 'esm',
  banner: {
    js: "import { createRequire } from 'node:module'; const require = createRequire(import.meta.url);",
  },
})

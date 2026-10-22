import { cp, mkdir, mkdtemp, readFile, writeFile, access } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { tmpdir } from 'node:os'
import { fileURLToPath } from 'node:url'
import { spawn } from 'node:child_process'

const uiRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const packageRoot = join(uiRoot, 'packages/webos')
const demoRoot = join(uiRoot, 'examples/webos-demo')

function run(args, cwd) {
  return new Promise((resolveRun, reject) => {
    const child = spawn('pnpm', args, {
      cwd,
      stdio: 'inherit',
      shell: process.platform === 'win32',
    })
    child.on('error', reject)
    child.on('close', (code) =>
      code === 0 ? resolveRun() : reject(new Error(`pnpm ${args.join(' ')} exited with ${code}`)),
    )
  })
}

let tempRoot = tmpdir()
try {
  await access('/tmp/opencode')
  tempRoot = '/tmp/opencode'
} catch {
  /* Portable fallback. */
}
const work = await mkdtemp(join(tempRoot, 'webos-consumer-'))
const consumer = join(work, 'consumer')
await mkdir(consumer)
await run(['pack', '--pack-destination', work], packageRoot)
const pkg = JSON.parse(await readFile(join(packageRoot, 'package.json'), 'utf8'))
if (pkg.dependencies?.['naive-ui'] || pkg.peerDependencies?.['naive-ui']) {
  throw new Error('The WebOS package must not require Naive UI.')
}
const tarball = join(work, `host-deck-webos-${pkg.version}.tgz`)
const demo = JSON.parse(await readFile(join(demoRoot, 'package.json'), 'utf8'))
demo.dependencies['@host-deck/webos'] = `file:${tarball}`
await writeFile(join(consumer, 'package.json'), JSON.stringify(demo, null, 2))
for (const file of ['src', 'index.html', 'tsconfig.json', 'vite.config.ts', 'vitest.config.ts']) {
  await cp(join(demoRoot, file), join(consumer, file), { recursive: true })
}
await run(['install', '--ignore-scripts', '--prefer-offline'], consumer)
await run(['build'], consumer)
await run(['test'], consumer)
await access(join(consumer, 'node_modules/@host-deck/webos/LICENSE'))
const css = await readFile(join(consumer, 'node_modules/@host-deck/webos/dist/webos.css'), 'utf8')
if (!css.includes('.webos-root') || /(^|[}])(?:body|html|:root|\*)\s*[{]/.test(css)) {
  throw new Error('WebOS CSS is missing its scope or includes a global reset.')
}
const js = await readFile(join(consumer, 'node_modules/@host-deck/webos/dist/webos.js'), 'utf8')
if (/['"]naive-ui['"]/.test(js)) {
  throw new Error('The distributed package still imports Naive UI.')
}
if (/['"]@\/|\/api\/|window\.hostDeck|VITE_DEV_PROXY_TARGET/.test(js)) {
  throw new Error('The distributed package contains HostDeck-specific dependencies.')
}
console.log(`Packed WebOS verified in independent consumer: ${consumer}`)

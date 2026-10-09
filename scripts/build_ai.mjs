import { spawnSync } from 'node:child_process'
import { copyFileSync, cpSync, mkdirSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const target = process.argv[2]
if (!target) throw new Error('Usage: node scripts/build_ai.mjs <bundle-directory>')
const [major, minor] = process.versions.node.split('.').map(Number)
if (major < 22 || (major === 22 && minor < 19)) throw new Error('pi-ai requires Node.js >=22.19.0')
const packageManager = process.platform === 'win32' ? 'pnpm.cmd' : 'pnpm'
for (const args of [['install', '--frozen-lockfile'], ['run', 'build']]) {
  const result = spawnSync(packageManager, args, {
    cwd: path.join(root, 'host-deck-ai'), stdio: 'inherit', shell: process.platform === 'win32',
  })
  if (result.status !== 0) process.exit(result.status || 1)
}
const destination = path.resolve(target, 'ai')
mkdirSync(destination, { recursive: true })
copyFileSync(path.join(root, 'host-deck-ai', 'dist', 'bridge.mjs'), path.join(destination, 'bridge.mjs'))
cpSync(path.join(root, 'host-deck-ai', 'node_modules'), path.join(destination, 'node_modules'), { recursive: true })
// Build on the target OS/architecture, just like the Dart executable.
copyFileSync(process.execPath, path.join(destination, process.platform === 'win32' ? 'node.exe' : 'node'))

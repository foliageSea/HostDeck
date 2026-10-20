import { spawnSync } from 'node:child_process'
import { chmodSync, mkdirSync, rmSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const target = process.argv[2]
if (!target) throw new Error('Usage: node scripts/build_ai.mjs <bundle-directory>')
const packageDir = path.join(root, 'host-deck-ai')
const packageManager = process.platform === 'win32' ? 'pnpm.cmd' : 'pnpm'
const result = spawnSync(packageManager, ['install', '--frozen-lockfile'], {
  cwd: packageDir,
  stdio: 'inherit',
  shell: process.platform === 'win32',
})
if (result.status !== 0) process.exit(result.status || 1)

const destination = path.resolve(target, 'ai')
mkdirSync(destination, { recursive: true })
for (const legacy of ['bridge.mjs', 'node', 'node.exe', 'node_modules']) {
  rmSync(path.join(destination, legacy), { recursive: true, force: true })
}

const bunTarget = process.env.HOSTDECK_AI_BUN_TARGET
const windowsTarget = bunTarget?.includes('windows') ?? process.platform === 'win32'
const output = path.join(destination, windowsTarget ? 'bridge.exe' : 'bridge')
const build = spawnSync(
  process.execPath,
  [path.join(packageDir, 'build-bin.mjs'), output, ...(bunTarget ? [bunTarget] : [])],
  { cwd: packageDir, stdio: 'inherit' },
)
if (build.status !== 0) process.exit(build.status || 1)
if (!windowsTarget) chmodSync(output, 0o755)

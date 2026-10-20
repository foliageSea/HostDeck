import { spawnSync } from 'node:child_process'
import { existsSync, readdirSync } from 'node:fs'
import path from 'node:path'

const binary = path.resolve('dist', process.platform === 'win32' ? 'bridge.exe' : 'bridge')
if (!existsSync(binary)) {
  console.error('Compiled bridge is missing. Run pnpm run build:bin first.')
  process.exit(1)
}

const tests = readdirSync('test')
  .filter((name) => name.endsWith('.test.mjs'))
  .map((name) => path.join('test', name))
const result = spawnSync(process.execPath, ['--test', ...tests], {
  stdio: 'inherit',
  env: { ...process.env, HOSTDECK_AI_BRIDGE_BIN: binary },
})
process.exit(result.status ?? 1)

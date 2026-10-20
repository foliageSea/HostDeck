import { spawnSync } from 'node:child_process'
import { chmodSync, mkdirSync } from 'node:fs'
import path from 'node:path'

const targetArg = process.argv[3] ?? process.env.HOSTDECK_AI_BUN_TARGET
const windowsTarget = targetArg?.includes('windows') ?? process.platform === 'win32'
const output = path.resolve(
  process.argv[2] ?? path.join('dist', windowsTarget ? 'bridge.exe' : 'bridge'),
)
const bun = process.env.HOSTDECK_AI_BUN ?? (process.platform === 'win32' ? 'bun.exe' : 'bun')

mkdirSync(path.dirname(output), { recursive: true })
const args = ['build', 'src/bridge.mjs', '--compile', '--minify', '--outfile', output]
if (targetArg) args.push(`--target=${targetArg}`)
if (windowsTarget) args.push('--windows-hide-console')

const result = spawnSync(bun, args, { stdio: 'inherit' })
if (result.error) {
  console.error(`Unable to run Bun (${bun}). Install Bun 1.4+ or set HOSTDECK_AI_BUN.`)
  console.error(result.error.message)
  process.exit(1)
}
if (result.status !== 0) process.exit(result.status ?? 1)
if (!windowsTarget) chmodSync(output, 0o755)
console.log(`Built ${output}`)

import { spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../', import.meta.url))
const [
  version = process.env.HOSTDECK_VERSION || 'dev',
  directory = 'build/sidecar-assets',
  ...extra
] = process.argv.slice(2)
const usage = 'pnpm run build:sidecar [version] [output-dir]'

if (version === '--help' || version === '-h') {
  console.log(usage)
  console.log(
    'Requires Docker Buildx. Relative output paths are resolved from the repository root.',
  )
  process.exit(0)
}
if (!version || !directory || extra.length) {
  console.error('Usage: ' + usage)
  process.exit(1)
}

const output = path.resolve(root, directory)
// Buildx parses export options as CSV; quote the entire destination field.
const exportOptions = 'type=local,"' + ('dest=' + output).replaceAll('"', '""') + '"'

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit' })
  if (result.error) throw result.error
  if (result.status !== 0) process.exit(result.status ?? 1)
}

try {
  run('docker', [
    'buildx',
    'build',
    '--target',
    'sidecar-assets',
    '--build-arg',
    'HOSTDECK_VERSION=' + version,
    '--output',
    exportOptions,
    '.',
  ])
  run(process.execPath, ['scripts/sidecar_assets.mjs', 'verify', output, version])
  console.log('SideCar assets verified: ' + output)
} catch (error) {
  console.error('SideCar build: ' + error.message)
  process.exitCode = 1
}

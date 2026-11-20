const { spawnSync } = require('node:child_process')
const fs = require('node:fs')
const path = require('node:path')

const { projectRoot, repoRoot } = require('../shared/project-paths.cjs')

const outputDir = path.join(repoRoot, 'build', 'electron-server')
// Use the SDK executable on Windows so paths with spaces need no cmd.exe quoting.
const dart = process.platform === 'win32' ? 'dart.exe' : 'dart'
const serverName = process.platform === 'win32' ? 'server.exe' : 'server'
const bundleDir = path.join(outputDir, 'bundle')
const serverExecutable = path.join(bundleDir, 'bin', serverName)

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    stdio: 'inherit',
  })

  if (result.error) {
    console.error(`Failed to start ${command}: ${result.error.message}`)
  }
  if (result.status !== 0) process.exit(result.status || 1)
}

fs.rmSync(outputDir, { recursive: true, force: true })

run(dart, ['pub', 'get'])
run(dart, ['build', 'cli', '--target', path.join('bin', 'server.dart'), '--output', outputDir])
run(process.execPath, [path.join('scripts', 'sidecar_assets.mjs'), 'stage', bundleDir])
run(process.execPath, [path.join('scripts', 'build_ai.mjs'), bundleDir])

if (!fs.existsSync(serverExecutable)) {
  console.error('Server executable was not generated: ' + serverExecutable)
  process.exit(1)
}

if (!fs.existsSync(projectRoot)) {
  console.error('Project root was not found: ' + projectRoot)
  process.exit(1)
}

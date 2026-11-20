const { spawnSync } = require('node:child_process')
const fs = require('node:fs')
const path = require('node:path')

const { projectRoot, repoRoot } = require('../shared/project-paths.cjs')

const outputDir = path.join(repoRoot, 'build', 'electron-server')
const packageConfig = path.join(repoRoot, '.dart_tool', 'package_config.json')
const serverName = process.platform === 'win32' ? 'server.exe' : 'server'
const bundleDir = path.join(outputDir, 'bundle')
const serverExecutable = path.join(bundleDir, 'bin', serverName)

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    shell: process.platform === 'win32' && command !== process.execPath,
    stdio: 'inherit',
  })

  if (result.status !== 0 && !options.allowFailure) {
    process.exit(result.status || 1)
  }

  return result.status || 0
}

fs.rmSync(outputDir, { recursive: true, force: true })

const pubGetStatus = run('flutter', ['pub', 'get'], { allowFailure: true })
if (pubGetStatus !== 0 && !fs.existsSync(packageConfig)) {
  process.exit(pubGetStatus)
}
if (pubGetStatus !== 0) {
  console.warn('flutter pub get failed; continuing with existing .dart_tool/package_config.json.')
}

run('dart', ['build', 'cli', '--target', path.join('bin', 'server.dart'), '--output', outputDir])
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

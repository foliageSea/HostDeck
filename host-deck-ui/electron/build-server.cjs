const { spawnSync } = require('node:child_process')
const fs = require('node:fs')
const path = require('node:path')

if (process.platform !== 'win32') {
  console.error('Electron Windows server build must run on Windows.')
  process.exit(1)
}

const uiRoot = path.resolve(__dirname, '..')
const repoRoot = path.resolve(uiRoot, '..')
const outputDir = path.join(repoRoot, 'build', 'electron-server')
const packageConfig = path.join(repoRoot, '.dart_tool', 'package_config.json')
const serverExe = path.join(outputDir, 'bundle', 'bin', 'server.exe')

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    shell: process.platform === 'win32',
    stdio: 'inherit',
  })

  if (result.status !== 0 && !options.allowFailure) {
    process.exit(result.status || 1)
  }

  return result.status || 0
}

fs.rmSync(outputDir, { recursive: true, force: true })
fs.mkdirSync(outputDir, { recursive: true })

const pubGetStatus = run('flutter', ['pub', 'get'], { allowFailure: true })
if (pubGetStatus !== 0 && !fs.existsSync(packageConfig)) {
  process.exit(pubGetStatus)
}
if (pubGetStatus !== 0) {
  console.warn('flutter pub get failed; continuing with existing .dart_tool/package_config.json.')
}

run('dart', [
  'build',
  'cli',
  '--target',
  path.join(repoRoot, 'bin', 'server.dart'),
  '--output',
  outputDir,
])

if (!fs.existsSync(serverExe)) {
  console.error('Server executable was not generated: ' + serverExe)
  process.exit(1)
}

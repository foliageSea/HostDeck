const { spawn } = require('node:child_process')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

const { resolveConfiguredDevUrl, waitForUrl } = require('../shared/dev-server.cjs')
const {
  frontendRoot,
  frontendViteConfigPath,
  projectRoot,
  repoRoot,
  shellViteConfigPath,
} = require('../shared/project-paths.cjs')

const children = []
const devLockPath = path.join(os.tmpdir(), 'host-deck-electron-dev.lock')
let releaseDevLock = null

function isProcessRunning(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false

  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    return error.code === 'EPERM'
  }
}

function acquireDevModeLock() {
  try {
    const fd = fs.openSync(devLockPath, 'wx')
    fs.writeFileSync(fd, String(process.pid))
    fs.closeSync(fd)
    return true
  } catch (error) {
    if (error.code !== 'EEXIST') throw error

    const existingPid = Number(fs.readFileSync(devLockPath, 'utf-8'))
    if (isProcessRunning(existingPid)) return false

    fs.rmSync(devLockPath, { force: true })
    return acquireDevModeLock()
  }
}

function removeDevModeLock() {
  try {
    if (fs.readFileSync(devLockPath, 'utf-8') === String(process.pid)) {
      fs.rmSync(devLockPath, { force: true })
    }
  } catch {
    // The lock may already be removed during shutdown.
  }
}

function run(command, args, env = {}, cwd = projectRoot) {
  const child = spawn(command, args, {
    cwd,
    env: { ...process.env, ...env },
    shell: process.platform === 'win32',
    stdio: 'inherit',
  })
  children.push(child)
  return child
}

function stopAll() {
  for (const child of children) {
    if (!child.killed) child.kill()
  }
  if (releaseDevLock) releaseDevLock()
}

process.on('SIGINT', () => {
  stopAll()
  process.exit(130)
})

process.on('SIGTERM', () => {
  stopAll()
  process.exit(143)
})

async function main() {
  if (!acquireDevModeLock()) {
    const shellDevUrl = await resolveConfiguredDevUrl({
      configFile: shellViteConfigPath,
      envVarName: 'HOST_DECK_ELECTRON_SHELL_DEV_URL',
      fallbackPort: 5180,
    })
    const appDevUrl = await resolveConfiguredDevUrl({
      configFile: frontendViteConfigPath,
      envVarName: 'HOST_DECK_ELECTRON_APP_DEV_URL',
      fallbackPort: 5178,
    })
    const electron = run(
      'pnpm',
      ['exec', 'electron', '.'],
      {
        HOST_DECK_ELECTRON_APP_DEV_URL: appDevUrl,
        HOST_DECK_ELECTRON_SHELL_DEV_URL: shellDevUrl,
      },
      projectRoot
    )

    electron.on('exit', (code) => {
      process.exit(code || 0)
    })
    return
  }
  releaseDevLock = removeDevModeLock

  const shellDevUrl = await resolveConfiguredDevUrl({
    configFile: shellViteConfigPath,
    envVarName: 'HOST_DECK_ELECTRON_SHELL_DEV_URL',
    fallbackPort: 5180,
  })
  const appDevUrl = await resolveConfiguredDevUrl({
    configFile: frontendViteConfigPath,
    envVarName: 'HOST_DECK_ELECTRON_APP_DEV_URL',
    fallbackPort: 5178,
  })

  run('pnpm', ['dev'])
  run('pnpm', ['--dir', frontendRoot, 'dev'], {}, repoRoot)

  await Promise.all([waitForUrl(shellDevUrl, 30000), waitForUrl(appDevUrl, 30000)])

  const electron = run(
    'pnpm',
    ['exec', 'electron', '.'],
    {
      HOST_DECK_ELECTRON_APP_DEV_URL: appDevUrl,
      HOST_DECK_ELECTRON_SHELL_DEV_URL: shellDevUrl,
    },
    projectRoot
  )

  electron.on('exit', (code) => {
    stopAll()
    process.exit(code || 0)
  })
}

main().catch((error) => {
  console.error(error)
  stopAll()
  process.exit(1)
})

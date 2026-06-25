const { spawn } = require('node:child_process')

const { resolveConfiguredDevUrl, waitForUrl } = require('../shared/dev-server.cjs')
const {
  frontendRoot,
  frontendViteConfigPath,
  projectRoot,
  repoRoot,
  shellViteConfigPath,
} = require('../shared/project-paths.cjs')

const children = []

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

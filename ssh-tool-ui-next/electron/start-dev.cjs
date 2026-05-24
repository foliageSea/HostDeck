const { spawn } = require('node:child_process')
const http = require('node:http')

const viteUrl = process.env.SSH_TOOL_ELECTRON_DEV_URL || 'http://localhost:5174'
const children = []

function run(command, args, env = {}) {
  const child = spawn(command, args, {
    env: { ...process.env, ...env },
    shell: process.platform === 'win32',
    stdio: 'inherit',
  })
  children.push(child)
  return child
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function ping(url) {
  return new Promise((resolve, reject) => {
    const request = http.get(url, (response) => {
      response.resume()
      resolve()
    })
    request.on('error', reject)
    request.setTimeout(1000, () => request.destroy(new Error('timeout')))
  })
}

async function waitFor(url) {
  const deadline = Date.now() + 30000
  while (Date.now() < deadline) {
    try {
      await ping(url)
      return
    } catch {
      await sleep(300)
    }
  }
  throw new Error('Vite dev server did not start: ' + url)
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
  run('pnpm', ['dev'])
  await waitFor(viteUrl)
  const electron = run('pnpm', ['exec', 'electron', '.'])
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

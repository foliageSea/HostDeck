const { spawn } = require('node:child_process')
const path = require('node:path')

function createServerRuntime({ app, frontendRoot, isPackaged, readSettings, repoRoot }) {
  let serverProcess = null

  function allowExternalAccess() {
    return readSettings().allowExternalAccess === true
  }

  function serverPort() {
    const port = Number(process.env.HOST_DECK_ELECTRON_PORT)
    return Number.isInteger(port) && port > 0 && port <= 65535 ? port : 18080
  }

  function start() {
    const port = serverPort()
    const host = allowExternalAccess() ? '0.0.0.0' : '127.0.0.1'
    const localUrl = `http://127.0.0.1:${port}`
    const webDir = isPackaged() ? path.join(process.resourcesPath, 'web') : path.join(frontendRoot, 'dist')
    const dataDir = path.join(app.getPath('userData'), 'data')
    const command = isPackaged()
      ? path.join(process.resourcesPath, 'server', 'server.exe')
      : process.env.HOST_DECK_DART_COMMAND || 'dart'
    const args = isPackaged()
      ? []
      : ['run', path.join(repoRoot, 'bin', 'server.dart')]

    args.push('--host', host)
    args.push('--port', String(port))
    args.push('--web-dir', webDir)
    args.push('--data-dir', dataDir)

    serverProcess = spawn(command, args, {
      cwd: isPackaged() ? process.resourcesPath : repoRoot,
      stdio: 'inherit',
      windowsHide: true,
    })
    const child = serverProcess

    serverProcess.on('exit', (code, signal) => {
      if (code !== 0 && signal !== 'SIGTERM') {
        console.error('HostDeck server exited:', code, signal)
      }
      if (serverProcess === child) serverProcess = null
    })

    return localUrl
  }

  function stop() {
    if (!serverProcess) return Promise.resolve()
    const child = serverProcess

    return new Promise((resolve) => {
      const timer = setTimeout(resolve, 3000)
      child.once('exit', () => {
        clearTimeout(timer)
        resolve()
      })
      serverProcess = null

      if (process.platform === 'win32') {
        spawn('taskkill', ['/pid', String(child.pid), '/f', '/t'])
        return
      }

      child.kill('SIGTERM')
    })
  }

  return {
    start,
    stop,
  }
}

module.exports = {
  createServerRuntime,
}

const { spawn } = require('node:child_process')
const fs = require('node:fs')
const net = require('node:net')
const path = require('node:path')

function createServerRuntime({ app, frontendRoot, isPackaged, readSettings, repoRoot }) {
  let serverProcess = null
  let serverLogStream = null

  function allowExternalAccess() {
    return readSettings().allowExternalAccess === true
  }

  function serverPort() {
    const port = Number(process.env.HOST_DECK_ELECTRON_PORT)
    return Number.isInteger(port) && port > 0 && port <= 65535 ? port : 18080
  }

  function serverLogPath() {
    return path.join(app.getPath('userData'), 'logs', 'server.log')
  }

  function openServerLogStream() {
    if (!isPackaged()) return null

    const logPath = serverLogPath()
    fs.mkdirSync(path.dirname(logPath), { recursive: true })
    const stream = fs.createWriteStream(logPath, { flags: 'a' })
    stream.write(`\n[${new Date().toISOString()}] Starting HostDeck server\n`)
    return stream
  }

  function closeServerLogStream(stream) {
    if (!stream || stream.destroyed || stream.writableEnded) return
    stream.end(`[${new Date().toISOString()}] HostDeck server log closed\n`)
    if (serverLogStream === stream) serverLogStream = null
  }

  function writeServerLog(stream, message) {
    if (!stream || stream.destroyed || stream.writableEnded) return
    stream.write(message)
  }

  function canBind(host, port) {
    return new Promise((resolve) => {
      const tester = net.createServer()
      tester.once('error', () => resolve(false))
      tester.once('listening', () => {
        tester.close(() => resolve(true))
      })
      tester.listen(port, host)
    })
  }

  function resolveFreePort(host) {
    return new Promise((resolve, reject) => {
      const tester = net.createServer()
      tester.once('error', reject)
      tester.once('listening', () => {
        const address = tester.address()
        tester.close(() => resolve(address.port))
      })
      tester.listen(0, host)
    })
  }

  async function resolveServerPort(host, logStream) {
    const preferredPort = serverPort()
    if (await canBind(host, preferredPort)) return preferredPort

    const port = await resolveFreePort(host)
    writeServerLog(
      logStream,
      `[${new Date().toISOString()}] Preferred port ${preferredPort} is unavailable; using ${port}\n`
    )
    return port
  }

  async function start() {
    const host = allowExternalAccess() ? '0.0.0.0' : '127.0.0.1'
    const webDir = isPackaged()
      ? path.join(process.resourcesPath, 'web')
      : path.join(frontendRoot, 'dist')
    const dataDir = path.join(app.getPath('userData'), 'data')
    const command = isPackaged()
      ? path.join(process.resourcesPath, 'server', 'server.exe')
      : process.env.HOST_DECK_DART_COMMAND || 'dart'
    const args = isPackaged() ? [] : ['run', path.join(repoRoot, 'bin', 'server.dart')]
    const packaged = isPackaged()
    const logStream = openServerLogStream()
    serverLogStream = logStream
    const port = await resolveServerPort(host, logStream)
    const localUrl = `http://127.0.0.1:${port}`

    args.push('--host', host)
    args.push('--port', String(port))
    args.push('--web-dir', webDir)
    args.push('--data-dir', dataDir)

    if (logStream) {
      writeServerLog(logStream, `command: ${command}\n`)
      writeServerLog(logStream, `args: ${args.join(' ')}\n`)
      writeServerLog(logStream, `cwd: ${process.resourcesPath}\n`)
    }

    serverProcess = spawn(command, args, {
      cwd: packaged ? process.resourcesPath : repoRoot,
      stdio: packaged ? ['ignore', 'pipe', 'pipe'] : 'inherit',
      windowsHide: true
    })
    const child = serverProcess

    if (logStream) {
      child.stdout?.pipe(logStream, { end: false })
      child.stderr?.pipe(logStream, { end: false })
    }

    serverProcess.on('error', (error) => {
      if (logStream) {
        writeServerLog(
          logStream,
          `[${new Date().toISOString()}] Failed to start HostDeck server: ${error.stack || error}\n`
        )
        closeServerLogStream(logStream)
      } else {
        console.error('Failed to start HostDeck server:', error)
      }
    })

    serverProcess.on('exit', (code, signal) => {
      if (logStream) {
        writeServerLog(
          logStream,
          `[${new Date().toISOString()}] HostDeck server exited: code=${code} signal=${signal}\n`
        )
        closeServerLogStream(logStream)
      }
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
    stop
  }
}

module.exports = {
  createServerRuntime
}

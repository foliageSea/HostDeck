const { app, BrowserWindow, ipcMain, shell } = require('electron')
const { spawn } = require('node:child_process')
const http = require('node:http')
const path = require('node:path')

const uiRoot = path.resolve(__dirname, '..')
const repoRoot = path.resolve(uiRoot, '..')
const devUrl = process.env.SSH_TOOL_ELECTRON_DEV_URL || 'http://localhost:5174'
const useDevServer = !app.isPackaged && process.env.SSH_TOOL_ELECTRON_MODE !== 'preview'

let mainWindow
let serverProcess

function serverPort() {
  const port = Number(process.env.SSH_TOOL_ELECTRON_PORT)
  return Number.isInteger(port) && port > 0 && port <= 65535 ? port : 18080
}

function ping(url) {
  return new Promise((resolve, reject) => {
    const req = http.get(url, (res) => {
      res.resume()
      resolve()
    })
    req.on('error', reject)
    req.setTimeout(1000, () => req.destroy(new Error('Request timeout')))
  })
}

async function waitFor(url) {
  const deadline = Date.now() + 15000
  while (Date.now() < deadline) {
    try {
      await ping(url)
      return
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 250))
    }
  }
  throw new Error('Server did not start: ' + url)
}

function startServer() {
  const port = serverPort()
  const host = '127.0.0.1'
  const webDir = path.join(uiRoot, 'dist')
  const dataDir = path.join(app.getPath('userData'), 'data')
  const args = ['run', path.join(repoRoot, 'bin', 'server.dart')]
  args.push('--host', host)
  args.push('--port', String(port))
  args.push('--web-dir', webDir)
  args.push('--data-dir', dataDir)

  serverProcess = spawn(process.env.SSH_TOOL_DART_COMMAND || 'dart', args, {
    cwd: repoRoot,
    stdio: 'inherit',
    windowsHide: true,
  })

  serverProcess.on('exit', (code, signal) => {
    if (code !== 0 && signal !== 'SIGTERM') {
      console.error('SSH Tool server exited:', code, signal)
    }
    serverProcess = null
  })

  return 'http://' + host + ':' + port
}

function stopServer() {
  if (!serverProcess) return
  const child = serverProcess
  serverProcess = null
  if (process.platform === 'win32') {
    spawn('taskkill', ['/pid', String(child.pid), '/f', '/t'])
    return
  }
  child.kill('SIGTERM')
}

function createWindow(url) {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 1024,
    minHeight: 720,
    title: 'SSH Tool',
    frame: false,
    titleBarStyle: 'hidden',
    trafficLightPosition: { x: 16, y: 14 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  })

  mainWindow.webContents.setWindowOpenHandler(({ url: nextUrl }) => {
    shell.openExternal(nextUrl)
    return { action: 'deny' }
  })

  mainWindow.loadURL(url)
  mainWindow.on('closed', () => {
    mainWindow = null
  })
}

ipcMain.handle('window:minimize', (event) => {
  BrowserWindow.fromWebContents(event.sender)?.minimize()
})

ipcMain.handle('window:toggle-maximize', (event) => {
  const window = BrowserWindow.fromWebContents(event.sender)
  if (!window) return false

  if (window.isMaximized()) {
    window.unmaximize()
    return false
  }

  window.maximize()
  return true
})

ipcMain.handle('window:close', (event) => {
  BrowserWindow.fromWebContents(event.sender)?.close()
})

app.whenReady().then(async () => {
  const url = useDevServer ? devUrl : startServer()
  if (!useDevServer) await waitFor(url)
  createWindow(url)

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow(url)
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

app.on('before-quit', () => {
  stopServer()
})

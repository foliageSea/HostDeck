const { app, BrowserWindow, ipcMain, session, shell } = require('electron')
const { spawn } = require('node:child_process')
const fs = require('node:fs')
const http = require('node:http')
const path = require('node:path')

const uiRoot = path.resolve(__dirname, '..')
const repoRoot = path.resolve(uiRoot, '..')
const devUrl = process.env.SSH_TOOL_ELECTRON_DEV_URL || 'http://localhost:5174'
const useDevServer = !app.isPackaged && process.env.SSH_TOOL_ELECTRON_MODE !== 'preview'
const isPackaged = app.isPackaged

let mainWindow
let serverProcess

function electronSettingsPath() {
  return path.join(app.getPath('userData'), 'electron-settings.json')
}

function readElectronSettings() {
  try {
    const rawValue = fs.readFileSync(electronSettingsPath(), 'utf8')
    const value = JSON.parse(rawValue)
    return value && typeof value === 'object' ? value : {}
  } catch {
    return {}
  }
}

function writeElectronSettings(settings) {
  const settingsPath = electronSettingsPath()
  fs.mkdirSync(path.dirname(settingsPath), { recursive: true })
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2))
}

function allowExternalAccess() {
  return readElectronSettings().allowExternalAccess === true
}

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
  const host = allowExternalAccess() ? '0.0.0.0' : '127.0.0.1'
  const localUrl = 'http://127.0.0.1:' + port
  const webDir = isPackaged ? path.join(process.resourcesPath, 'web') : path.join(uiRoot, 'dist')
  const dataDir = path.join(app.getPath('userData'), 'data')
  const command = isPackaged
    ? path.join(process.resourcesPath, 'server', 'server.exe')
    : process.env.SSH_TOOL_DART_COMMAND || 'dart'
  const args = isPackaged ? [] : ['run', path.join(repoRoot, 'bin', 'server.dart')]
  args.push('--host', host)
  args.push('--port', String(port))
  args.push('--web-dir', webDir)
  args.push('--data-dir', dataDir)

  serverProcess = spawn(command, args, {
    cwd: isPackaged ? process.resourcesPath : repoRoot,
    stdio: 'inherit',
    windowsHide: true,
  })
  const child = serverProcess

  serverProcess.on('exit', (code, signal) => {
    if (code !== 0 && signal !== 'SIGTERM') {
      console.error('SSH Tool server exited:', code, signal)
    }
    if (serverProcess === child) serverProcess = null
  })

  return localUrl
}

function stopServer() {
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

async function restartServer() {
  if (useDevServer) return devUrl

  await stopServer()
  const url = startServer()
  await waitFor(url)
  mainWindow?.loadURL(url)
  return url
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

ipcMain.handle('app:open-in-browser', async (event) => {
  const window = BrowserWindow.fromWebContents(event.sender)
  const url = window?.webContents.getURL()
  if (!url) return

  await shell.openExternal(url)
})

ipcMain.handle('app:clear-browser-cache', async () => {
  await session.defaultSession.clearCache()
})

ipcMain.handle('app:get-external-access', () => allowExternalAccess())

ipcMain.handle('app:set-external-access', async (_event, enabled) => {
  const settings = readElectronSettings()
  settings.allowExternalAccess = enabled === true
  writeElectronSettings(settings)
  await restartServer()
  return settings.allowExternalAccess
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

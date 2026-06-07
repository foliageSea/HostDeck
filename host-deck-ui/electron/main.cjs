const { app, BrowserWindow, ipcMain, screen, session, shell } = require('electron')
const { spawn } = require('node:child_process')
const fs = require('node:fs')
const http = require('node:http')
const path = require('node:path')

const uiRoot = path.resolve(__dirname, '..')
const repoRoot = path.resolve(uiRoot, '..')
const useDevServer = !app.isPackaged && process.env.HOST_DECK_ELECTRON_MODE !== 'preview'
const isPackaged = app.isPackaged

let mainWindow
let serverProcess

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function getDefaultWindowSize() {
  const { width: workAreaWidth, height: workAreaHeight } = screen.getPrimaryDisplay().workAreaSize
  return {
    width: clamp(Math.round(workAreaWidth * 0.75), 1360, 1720),
    height: clamp(Math.round(workAreaHeight * 0.82), 840, 1100),
  }
}

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
  const port = Number(process.env.HOST_DECK_ELECTRON_PORT)
  return Number.isInteger(port) && port > 0 && port <= 65535 ? port : 18080
}

async function devServerUrl() {
  if (process.env.HOST_DECK_ELECTRON_DEV_URL) return process.env.HOST_DECK_ELECTRON_DEV_URL

  try {
    const { resolveConfig } = await import('vite')
    const config = await resolveConfig({}, 'serve')
    const port = Number(config.server.port)
    if (Number.isInteger(port) && port > 0 && port <= 65535) return 'http://localhost:' + port
  } catch (error) {
    console.warn('Unable to resolve Vite dev server URL:', error)
  }

  return 'http://localhost:5173'
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
    : process.env.HOST_DECK_DART_COMMAND || 'dart'
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
      console.error('HostDeck server exited:', code, signal)
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

function loadingPagePath() {
  return path.join(__dirname, 'loading.html')
}

function showLoadingPage() {
  if (!mainWindow || mainWindow.isDestroyed()) return
  mainWindow.loadFile(loadingPagePath())
}

async function restartServer() {
  if (useDevServer) return devServerUrl()

  await stopServer()
  const url = startServer()
  showLoadingPage()
  await waitFor(url)
  mainWindow?.loadURL(url)
  return url
}

function createWindow() {
  const { width, height } = getDefaultWindowSize()

  mainWindow = new BrowserWindow({
    width,
    height,
    minWidth: 1024,
    minHeight: 720,
    title: 'HostDeck',
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

  showLoadingPage()
  mainWindow.on('closed', () => {
    mainWindow = null
  })
}

async function loadApplication() {
  const url = useDevServer ? await devServerUrl() : startServer()
  await waitFor(url)
  if (mainWindow && !mainWindow.isDestroyed()) await mainWindow.loadURL(url)
  return url
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
  createWindow()
  const url = await loadApplication()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow()
      mainWindow?.loadURL(url)
    }
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

app.on('before-quit', () => {
  stopServer()
})

const { app, BrowserWindow, Menu, Tray, WebContentsView, ipcMain, nativeImage, screen, session, shell } = require('electron')
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
let applicationUrl = null
let activeTabId = null
let nextTabId = 1
let tray = null
let isQuitting = false
const tabs = new Map()
const tabOrder = []

const tabBarHeight = 42
const tabBarWidth = 220

function normalizeTabBarPosition(value) {
  return value === 'left' ? 'left' : 'top'
}

function tabBarPosition() {
  return normalizeTabBarPosition(readElectronSettings().tabBarPosition)
}

function tabLayoutMetrics() {
  return tabBarPosition() === 'left'
    ? { height: 0, width: tabBarWidth, x: tabBarWidth, y: 0 }
    : { height: tabBarHeight, width: 0, x: 0, y: tabBarHeight }
}

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

function tabsPagePath() {
  return path.join(__dirname, 'tabs.html')
}

function showLoadingPage() {
  if (!mainWindow || mainWindow.isDestroyed()) return
  mainWindow.loadFile(loadingPagePath())
}

function trayIcon() {
  const iconPath = path.join(__dirname, '..', 'public', 'favicon.png')
  return nativeImage.createFromPath(iconPath)
}

function showMainWindow() {
  if (!mainWindow || mainWindow.isDestroyed()) return
  if (mainWindow.isMinimized()) mainWindow.restore()
  mainWindow.show()
  mainWindow.focus()
}

function minimizeToTray() {
  if (!mainWindow || mainWindow.isDestroyed()) return
  mainWindow.hide()
}

function ensureTray() {
  if (tray) return tray

  tray = new Tray(trayIcon())
  tray.setToolTip('HostDeck')
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: '显示主窗口', click: showMainWindow },
      {
        label: '退出',
        click: () => {
          isQuitting = true
          app.quit()
        },
      },
    ]),
  )
  tray.on('double-click', showMainWindow)
  tray.on('click', showMainWindow)

  return tray
}

function getWindowFromSender(sender) {
  return BrowserWindow.fromWebContents(sender) ?? mainWindow ?? null
}

function serializeTabs() {
  return {
    activeTabId,
    tabBarPosition: tabBarPosition(),
    tabs: tabOrder.map((id) => tabs.get(id)).filter(Boolean).map((tab) => ({
      customTitle: tab.customTitle,
      id: tab.id,
      isActive: tab.id === activeTabId,
      isLoading: tab.isLoading,
      title: tab.title,
      url: tab.view.webContents.getURL(),
    })),
  }
}

function sendTabsChanged() {
  if (!mainWindow || mainWindow.isDestroyed()) return
  mainWindow.webContents.send('tabs:changed', serializeTabs())
}

function layoutActiveTab() {
  if (!mainWindow || mainWindow.isDestroyed() || !activeTabId) return

  const activeTab = tabs.get(activeTabId)
  if (!activeTab) return

  const bounds = mainWindow.getContentBounds()
  const layout = tabLayoutMetrics()
  activeTab.view.setBounds({
    x: layout.x,
    y: layout.y,
    width: Math.max(0, bounds.width - layout.width),
    height: Math.max(0, bounds.height - layout.height),
  })
}

function reorderTab(id, targetId, placement = 'after') {
  if (id === targetId) return serializeTabs()
  if (!tabs.has(id) || !tabs.has(targetId)) return serializeTabs()

  const fromIndex = tabOrder.indexOf(id)
  const targetIndex = tabOrder.indexOf(targetId)
  if (fromIndex < 0 || targetIndex < 0) return serializeTabs()

  const [movedId] = tabOrder.splice(fromIndex, 1)
  const nextTargetIndex = tabOrder.indexOf(targetId)
  const insertIndex = placement === 'before' ? nextTargetIndex : nextTargetIndex + 1
  tabOrder.splice(insertIndex, 0, movedId)
  sendTabsChanged()
  return serializeTabs()
}

function setTabBarPosition(position) {
  const nextPosition = normalizeTabBarPosition(position)
  const settings = readElectronSettings()
  if (normalizeTabBarPosition(settings.tabBarPosition) === nextPosition) {
    return serializeTabs()
  }

  settings.tabBarPosition = nextPosition
  writeElectronSettings(settings)
  layoutActiveTab()
  sendTabsChanged()
  return serializeTabs()
}

function attachTabView(tab) {
  if (!mainWindow || mainWindow.isDestroyed()) return
  mainWindow.contentView.addChildView(tab.view)
  layoutActiveTab()
}

function detachTabView(tab) {
  if (!mainWindow || mainWindow.isDestroyed()) return
  try {
    mainWindow.contentView.removeChildView(tab.view)
  } catch {
    // The view may already be detached during shutdown or fast tab switching.
  }
}

function updateTabTitle(tab, title) {
  if (tab.customTitle) return

  const normalizedTitle = typeof title === 'string' && title.trim() ? title.trim() : 'HostDeck'
  if (tab.title === normalizedTitle) return

  tab.title = normalizedTitle
  sendTabsChanged()
}

function createTab(url = applicationUrl) {
  if (!url) throw new Error('Application URL has not been initialized.')

  const id = `tab-${nextTabId++}`
  const view = new WebContentsView({
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  })
  const tab = {
    customTitle: null,
    id,
    isLoading: true,
    title: 'HostDeck',
    view,
  }

  tabs.set(id, tab)
  tabOrder.push(id)

  view.webContents.setWindowOpenHandler(({ url: nextUrl }) => {
    shell.openExternal(nextUrl)
    return { action: 'deny' }
  })
  view.webContents.on('page-title-updated', (event, title) => {
    event.preventDefault()
    updateTabTitle(tab, title)
  })
  view.webContents.on('did-start-loading', () => {
    tab.isLoading = true
    sendTabsChanged()
  })
  view.webContents.on('did-stop-loading', () => {
    tab.isLoading = false
    updateTabTitle(tab, view.webContents.getTitle())
    sendTabsChanged()
  })
  view.webContents.on('did-fail-load', () => {
    tab.isLoading = false
    sendTabsChanged()
  })
  view.webContents.on('destroyed', () => {
    tabs.delete(id)
    const orderIndex = tabOrder.indexOf(id)
    if (orderIndex >= 0) tabOrder.splice(orderIndex, 1)
    if (activeTabId === id) activeTabId = null
    sendTabsChanged()
  })

  view.webContents.loadURL(url)
  activateTab(id)
  return id
}

function activateTab(id) {
  const nextTab = tabs.get(id)
  if (!nextTab || activeTabId === id) return serializeTabs()

  const previousTab = activeTabId ? tabs.get(activeTabId) : null
  if (previousTab) detachTabView(previousTab)

  activeTabId = id
  attachTabView(nextTab)
  nextTab.view.webContents.focus()
  sendTabsChanged()
  return serializeTabs()
}

function closeTab(id) {
  const targetTab = tabs.get(id)
  if (!targetTab) return serializeTabs()

  const wasActive = activeTabId === id
  const closedIndex = tabOrder.indexOf(id)
  detachTabView(targetTab)
  tabs.delete(id)
  if (closedIndex >= 0) tabOrder.splice(closedIndex, 1)
  targetTab.view.webContents.close()

  if (wasActive) {
    activeTabId = null
    const fallbackId = tabOrder[Math.max(0, closedIndex - 1)] ?? tabOrder[0]
    const nextTab = fallbackId ? tabs.get(fallbackId) : null
    if (nextTab) {
      activateTab(nextTab.id)
    } else {
      sendTabsChanged()
    }
  } else {
    sendTabsChanged()
  }

  return serializeTabs()
}

function renameTab(id, title) {
  const targetTab = tabs.get(id)
  if (!targetTab) return serializeTabs()

  const normalizedTitle = typeof title === 'string' ? title.trim() : ''
  targetTab.customTitle = normalizedTitle || null
  targetTab.title = targetTab.customTitle || targetTab.view.webContents.getTitle() || 'HostDeck'
  sendTabsChanged()
  return serializeTabs()
}

function getActiveTab() {
  return activeTabId ? tabs.get(activeTabId) : null
}

function requireActiveTab() {
  const tab = getActiveTab()
  if (!tab) throw new Error('No active tab.')
  return tab
}

async function restartServer() {
  if (useDevServer) return devServerUrl()

  await stopServer()
  const url = startServer()
  await waitFor(url)
  applicationUrl = url
  for (const tab of tabs.values()) {
    tab.view.webContents.loadURL(url)
  }
  return url
}

function createWindow() {
  const { width, height } = getDefaultWindowSize()
  const macWindowOptions =
    process.platform === 'darwin' ? { trafficLightPosition: { x: 16, y: 15 } } : {}

  mainWindow = new BrowserWindow({
    width,
    height,
    minWidth: 1024,
    minHeight: 720,
    title: 'HostDeck',
    icon: path.join(__dirname, '..', 'public', 'favicon.png'),
    frame: false,
    titleBarStyle: 'hidden',
    ...macWindowOptions,
    webPreferences: {
      preload: path.join(__dirname, 'tabs-preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  })
  mainWindow.maximize()

  showLoadingPage()
  mainWindow.on('close', (event) => {
    if (isQuitting) return

    event.preventDefault()
    minimizeToTray()
  })
  mainWindow.on('resize', layoutActiveTab)
  mainWindow.on('maximize', layoutActiveTab)
  mainWindow.on('unmaximize', layoutActiveTab)
  mainWindow.on('closed', () => {
    mainWindow = null
  })
}

async function loadApplication() {
  const url = useDevServer ? await devServerUrl() : startServer()
  await waitFor(url)
  applicationUrl = url
  if (mainWindow && !mainWindow.isDestroyed()) {
    await mainWindow.loadFile(tabsPagePath())
    createTab(url)
  }
  return url
}

ipcMain.handle('window:minimize', (event) => {
  getWindowFromSender(event.sender)?.minimize()
})

ipcMain.handle('window:toggle-maximize', (event) => {
  const window = getWindowFromSender(event.sender)
  if (!window) return false

  if (window.isMaximized()) {
    window.unmaximize()
    return false
  }

  window.maximize()
  return true
})

ipcMain.handle('window:close', (event) => {
  getWindowFromSender(event.sender)?.close()
})

ipcMain.handle('app:open-in-browser', async (event) => {
  const activeTab = getActiveTab()
  const url = activeTab?.view.webContents.getURL()
  if (!url) return

  await shell.openExternal(url)
})

ipcMain.handle('app:open-devtools', (event) => {
  const activeTab = getActiveTab()
  if (activeTab) {
    activeTab.view.webContents.openDevTools({ mode: 'detach' })
    return
  }

  BrowserWindow.fromWebContents(event.sender)?.webContents.openDevTools({ mode: 'detach' })
})

ipcMain.handle('app:force-reload', (event) => {
  const activeTab = getActiveTab()
  if (activeTab) {
    activeTab.view.webContents.reloadIgnoringCache()
    return
  }

  BrowserWindow.fromWebContents(event.sender)?.webContents.reloadIgnoringCache()
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

ipcMain.handle('tabs:list', () => serializeTabs())

ipcMain.handle('tabs:create', () => createTab())

ipcMain.handle('tabs:activate', (_event, id) => activateTab(id))

ipcMain.handle('tabs:close', (_event, id) => closeTab(id))

ipcMain.handle('tabs:rename', (_event, id, title) => renameTab(id, title))

ipcMain.handle('tabs:reorder', (_event, id, targetId, placement) => reorderTab(id, targetId, placement))

ipcMain.handle('tabs:reload-active', () => {
  requireActiveTab().view.webContents.reloadIgnoringCache()
})

ipcMain.handle('tabs:open-active-devtools', () => {
  requireActiveTab().view.webContents.openDevTools({ mode: 'detach' })
})

ipcMain.handle('tabs:open-active-in-browser', async () => {
  const url = requireActiveTab().view.webContents.getURL()
  if (url) await shell.openExternal(url)
})

ipcMain.handle('tabs:set-bar-position', (_event, position) => setTabBarPosition(position))

app.whenReady().then(async () => {
  ensureTray()
  createWindow()
  const url = await loadApplication()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow()
      applicationUrl = url
      mainWindow?.loadFile(tabsPagePath())
      createTab(url)
    }
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin' && isQuitting) app.quit()
})

app.on('before-quit', () => {
  isQuitting = true
  stopServer()
})

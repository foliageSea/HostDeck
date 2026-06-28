const path = require('node:path')

const { app, BrowserWindow, Menu, Tray, WebContentsView, ipcMain, nativeImage, screen, session, shell } = require('electron')

const { createServerRuntime } = require('./server-runtime.cjs')
const { createSettingsStore } = require('./settings-store.cjs')
const { createShellPageLoader } = require('./shell-pages.cjs')
const { createTabManager } = require('./tab-manager.cjs')
const { registerIpcHandlers } = require('./ipc.cjs')
const { resolveConfiguredDevUrl, waitForUrl } = require('../shared/dev-server.cjs')
const {
  frontendRoot,
  frontendViteConfigPath,
  rendererHtmlRoot,
  repoRoot,
  shellViteConfigPath,
} = require('../shared/project-paths.cjs')

const isPreviewMode = process.env.HOST_DECK_ELECTRON_MODE === 'preview'
const useDevServers = !app.isPackaged && !isPreviewMode
const hasSingleInstanceLock = app.requestSingleInstanceLock()

let applicationUrl = null
let isQuitting = false
let mainWindow = null
let shellPageLoader = null
let tray = null

if (!hasSingleInstanceLock) {
  app.exit(0)
}

const settingsStore = createSettingsStore(app)
const serverRuntime = createServerRuntime({
  app,
  frontendRoot,
  isPackaged: () => app.isPackaged,
  readSettings: settingsStore.read,
  repoRoot,
})

const tabManager = createTabManager({
  WebContentsView,
  getApplicationUrl: () => applicationUrl,
  getMainWindow: () => mainWindow,
  preloadPath: path.join(__dirname, '..', 'preload', 'host-deck.cjs'),
  readSettings: settingsStore.read,
  shell,
  writeSettings: settingsStore.write,
})

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

function iconPath() {
  return app.isPackaged
    ? path.join(process.resourcesPath, 'icon.png')
    : path.join(frontendRoot, 'public', 'favicon.png')
}

function showMainWindow() {
  if (!mainWindow || mainWindow.isDestroyed()) return
  if (mainWindow.isMinimized()) mainWindow.restore()
  mainWindow.show()
  mainWindow.focus()
}

app.on('second-instance', showMainWindow)

function minimizeToTray() {
  if (!mainWindow || mainWindow.isDestroyed()) return
  mainWindow.hide()
}

function ensureTray() {
  if (tray) return tray

  tray = new Tray(nativeImage.createFromPath(iconPath()))
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
    ])
  )
  tray.on('double-click', showMainWindow)
  tray.on('click', showMainWindow)

  return tray
}

function getWindowFromSender(sender) {
  return BrowserWindow.fromWebContents(sender) ?? mainWindow ?? null
}

async function loadShellPage(pageName) {
  if (!mainWindow || mainWindow.isDestroyed()) return
  await shellPageLoader(mainWindow, pageName)
}

async function resolveAppUrl() {
  if (!useDevServers) return serverRuntime.start()

  return resolveConfiguredDevUrl({
    configFile: frontendViteConfigPath,
    envVarName: 'HOST_DECK_ELECTRON_APP_DEV_URL',
    fallbackPort: 5178,
  })
}

async function restartApplicationServer() {
  if (useDevServers) {
    applicationUrl = await resolveAppUrl()
    tabManager.reloadAll(applicationUrl)
    return applicationUrl
  }

  await serverRuntime.stop()
  applicationUrl = serverRuntime.start()
  await waitForUrl(applicationUrl, 15000)
  tabManager.reloadAll(applicationUrl)
  return applicationUrl
}

function createWindow() {
  const { width, height } = getDefaultWindowSize()
  const macWindowOptions = process.platform === 'darwin' ? { trafficLightPosition: { x: 16, y: 15 } } : {}

  mainWindow = new BrowserWindow({
    width,
    height,
    minWidth: 1024,
    minHeight: 720,
    title: 'HostDeck',
    icon: iconPath(),
    frame: false,
    titleBarStyle: 'hidden',
    ...macWindowOptions,
    webPreferences: {
      preload: path.join(__dirname, '..', 'preload', 'tabs.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  })
  mainWindow.maximize()

  loadShellPage('loading')
  mainWindow.on('close', (event) => {
    if (isQuitting) return
    event.preventDefault()
    minimizeToTray()
  })
  mainWindow.on('resize', tabManager.layoutActiveTab)
  mainWindow.on('maximize', tabManager.layoutActiveTab)
  mainWindow.on('unmaximize', tabManager.layoutActiveTab)
  mainWindow.on('closed', () => {
    mainWindow = null
  })
}

async function loadApplication() {
  applicationUrl = await resolveAppUrl()
  if (useDevServers) {
    await waitForUrl(applicationUrl, 15000)
  }
  await loadShellPage('tabs')
  tabManager.createTab(applicationUrl)
  return applicationUrl
}

registerIpcHandlers({
  getWindowFromSender,
  ipcMain,
  restartApplicationServer,
  session,
  settingsStore,
  shell,
  tabManager,
})

app.whenReady().then(async () => {
  const shellDevServerUrl = useDevServers
    ? await resolveConfiguredDevUrl({
        configFile: shellViteConfigPath,
        envVarName: 'HOST_DECK_ELECTRON_SHELL_DEV_URL',
        fallbackPort: 5180,
      })
    : null

  if (useDevServers) {
    await waitForUrl(shellDevServerUrl, 30000)
  }

  shellPageLoader = createShellPageLoader({
    rendererHtmlRoot,
    shellDevServerUrl,
    useShellDevServer: useDevServers,
  })

  ensureTray()
  createWindow()
  const url = await loadApplication()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length !== 0) return
    createWindow()
    applicationUrl = url
    loadShellPage('tabs').then(() => {
      tabManager.createTab(url)
    })
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin' && isQuitting) app.quit()
})

app.on('before-quit', () => {
  isQuitting = true
  serverRuntime.stop()
})

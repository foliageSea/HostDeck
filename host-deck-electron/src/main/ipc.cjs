function registerIpcHandlers({ getWindowFromSender, ipcMain, restartApplicationServer, session, settingsStore, shell, tabManager }) {
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

  ipcMain.handle('app:open-in-browser', async () => {
    const activeTab = tabManager.getActiveTab()
    const url = activeTab?.view.webContents.getURL()
    if (!url) return
    await shell.openExternal(url)
  })

  ipcMain.handle('app:open-devtools', (event) => {
    const activeTab = tabManager.getActiveTab()
    if (activeTab) {
      activeTab.view.webContents.openDevTools({ mode: 'detach' })
      return
    }

    getWindowFromSender(event.sender)?.webContents.openDevTools({ mode: 'detach' })
  })

  ipcMain.handle('app:force-reload', (event) => {
    const activeTab = tabManager.getActiveTab()
    if (activeTab) {
      activeTab.view.webContents.reloadIgnoringCache()
      return
    }

    getWindowFromSender(event.sender)?.webContents.reloadIgnoringCache()
  })

  ipcMain.handle('app:clear-browser-cache', async () => {
    await session.defaultSession.clearCache()
  })

  ipcMain.handle('app:get-external-access', () => settingsStore.read().allowExternalAccess === true)

  ipcMain.handle('app:set-external-access', async (_event, enabled) => {
    const settings = settingsStore.read()
    settings.allowExternalAccess = enabled === true
    settingsStore.write(settings)
    await restartApplicationServer()
    return settings.allowExternalAccess
  })

  ipcMain.handle('tabs:list', () => tabManager.serializeTabs())
  ipcMain.handle('tabs:create', () => tabManager.createTab())
  ipcMain.handle('tabs:activate', (_event, id) => tabManager.activateTab(id))
  ipcMain.handle('tabs:close', (_event, id) => tabManager.closeTab(id))
  ipcMain.handle('tabs:rename', (_event, id, title) => tabManager.renameTab(id, title))
  ipcMain.handle('tabs:reorder', (_event, id, targetId, placement) => tabManager.reorderTab(id, targetId, placement))
  ipcMain.handle('tabs:reload-active', () => {
    tabManager.requireActiveTab().view.webContents.reloadIgnoringCache()
  })
  ipcMain.handle('tabs:open-active-devtools', () => {
    tabManager.requireActiveTab().view.webContents.openDevTools({ mode: 'detach' })
  })
  ipcMain.handle('tabs:open-active-in-browser', async () => {
    const url = tabManager.requireActiveTab().view.webContents.getURL()
    if (url) await shell.openExternal(url)
  })
  ipcMain.handle('tabs:set-bar-position', (_event, position) => tabManager.setTabBarPosition(position))
}

module.exports = {
  registerIpcHandlers,
}

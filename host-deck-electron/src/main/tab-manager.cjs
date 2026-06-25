function createTabManager({ WebContentsView, getApplicationUrl, getMainWindow, preloadPath, readSettings, shell, writeSettings }) {
  const tabBarHeight = 42
  const tabBarWidth = 220

  let activeTabId = null
  let nextTabId = 1
  const tabs = new Map()
  const tabOrder = []

  function normalizeTabBarPosition(value) {
    return value === 'left' ? 'left' : 'top'
  }

  function tabBarPosition() {
    return normalizeTabBarPosition(readSettings().tabBarPosition)
  }

  function tabLayoutMetrics() {
    return tabBarPosition() === 'left'
      ? { height: 0, width: tabBarWidth, x: tabBarWidth, y: 0 }
      : { height: tabBarHeight, width: 0, x: 0, y: tabBarHeight }
  }

  function serializeTabs() {
    return {
      activeTabId,
      tabBarPosition: tabBarPosition(),
      tabs: tabOrder
        .map((id) => tabs.get(id))
        .filter(Boolean)
        .map((tab) => ({
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
    const mainWindow = getMainWindow()
    if (!mainWindow || mainWindow.isDestroyed()) return
    mainWindow.webContents.send('tabs:changed', serializeTabs())
  }

  function layoutActiveTab() {
    const mainWindow = getMainWindow()
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

  function attachTabView(tab) {
    const mainWindow = getMainWindow()
    if (!mainWindow || mainWindow.isDestroyed()) return
    mainWindow.contentView.addChildView(tab.view)
    layoutActiveTab()
  }

  function detachTabView(tab) {
    const mainWindow = getMainWindow()
    if (!mainWindow || mainWindow.isDestroyed()) return

    try {
      mainWindow.contentView.removeChildView(tab.view)
    } catch {
    }
  }

  function updateTabTitle(tab, title) {
    if (tab.customTitle) return

    const normalizedTitle = typeof title === 'string' && title.trim() ? title.trim() : 'HostDeck'
    if (tab.title === normalizedTitle) return

    tab.title = normalizedTitle
    sendTabsChanged()
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

  function createTab(url = getApplicationUrl()) {
    if (!url) throw new Error('Application URL has not been initialized.')

    const id = `tab-${nextTabId++}`
    const view = new WebContentsView({
      webPreferences: {
        preload: preloadPath,
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
    const settings = readSettings()
    if (normalizeTabBarPosition(settings.tabBarPosition) === nextPosition) {
      return serializeTabs()
    }

    settings.tabBarPosition = nextPosition
    writeSettings(settings)
    layoutActiveTab()
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

  function reloadAll(url) {
    for (const tab of tabs.values()) {
      tab.view.webContents.loadURL(url)
    }
  }

  return {
    activateTab,
    closeTab,
    createTab,
    getActiveTab,
    layoutActiveTab,
    reloadAll,
    renameTab,
    reorderTab,
    requireActiveTab,
    serializeTabs,
    setTabBarPosition,
  }
}

module.exports = {
  createTabManager,
}

const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('hostDeck', {
  app: {
    openInBrowser: () => ipcRenderer.invoke('app:open-in-browser'),
    openDevTools: () => ipcRenderer.invoke('app:open-devtools'),
    forceReload: () => ipcRenderer.invoke('app:force-reload'),
    clearBrowserCache: () => ipcRenderer.invoke('app:clear-browser-cache'),
    getExternalAccess: () => ipcRenderer.invoke('app:get-external-access'),
    setExternalAccess: (enabled) => ipcRenderer.invoke('app:set-external-access', enabled),
    getCloseAction: () => ipcRenderer.invoke('app:get-close-action'),
    setCloseAction: (value) => ipcRenderer.invoke('app:set-close-action', value),
  },
  platform: process.platform,
  shellMode: 'native-tabs',
  window: {
    minimize: () => ipcRenderer.invoke('window:minimize'),
    toggleMaximize: () => ipcRenderer.invoke('window:toggle-maximize'),
    close: () => ipcRenderer.invoke('window:close'),
  },
})

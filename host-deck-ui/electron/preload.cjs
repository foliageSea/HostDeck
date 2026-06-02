const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('hostDeck', {
  app: {
    openInBrowser: () => ipcRenderer.invoke('app:open-in-browser'),
    clearBrowserCache: () => ipcRenderer.invoke('app:clear-browser-cache'),
    getExternalAccess: () => ipcRenderer.invoke('app:get-external-access'),
    setExternalAccess: (enabled) => ipcRenderer.invoke('app:set-external-access', enabled),
  },
  platform: process.platform,
  window: {
    minimize: () => ipcRenderer.invoke('window:minimize'),
    toggleMaximize: () => ipcRenderer.invoke('window:toggle-maximize'),
    close: () => ipcRenderer.invoke('window:close'),
  },
})

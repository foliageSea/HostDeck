const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('hostDeck', {
  app: {
    openInBrowser: () => ipcRenderer.invoke('app:open-in-browser'),
    openDevTools: () => ipcRenderer.invoke('app:open-devtools'),
    forceReload: () => ipcRenderer.invoke('app:force-reload'),
    clearBrowserCache: () => ipcRenderer.invoke('app:clear-browser-cache'),
    getExternalAccess: () => ipcRenderer.invoke('app:get-external-access'),
    setExternalAccess: (enabled) => ipcRenderer.invoke('app:set-external-access', enabled)
  },
  platform: process.platform,
  shellMode: 'native-tabs',
  window: {
    getState: () => ipcRenderer.invoke('window:get-state'),
    minimize: () => ipcRenderer.invoke('window:minimize'),
    toggleMaximize: () => ipcRenderer.invoke('window:toggle-maximize'),
    close: () => ipcRenderer.invoke('window:close'),
    onStateChanged: (callback) => {
      const listener = (_event, state) => callback(state)
      ipcRenderer.on('window:state-changed', listener)
      return () => ipcRenderer.removeListener('window:state-changed', listener)
    }
  }
})

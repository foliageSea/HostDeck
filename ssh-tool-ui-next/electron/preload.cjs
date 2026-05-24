const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('sshTool', {
  app: {
    clearBrowserCache: () => ipcRenderer.invoke('app:clear-browser-cache'),
  },
  platform: process.platform,
  window: {
    minimize: () => ipcRenderer.invoke('window:minimize'),
    toggleMaximize: () => ipcRenderer.invoke('window:toggle-maximize'),
    close: () => ipcRenderer.invoke('window:close'),
  },
})

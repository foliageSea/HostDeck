const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('hostDeckTabs', {
  list: () => ipcRenderer.invoke('tabs:list'),
  create: () => ipcRenderer.invoke('tabs:create'),
  activate: (id) => ipcRenderer.invoke('tabs:activate', id),
  close: (id) => ipcRenderer.invoke('tabs:close', id),
  rename: (id, title) => ipcRenderer.invoke('tabs:rename', id, title),
  reloadActive: () => ipcRenderer.invoke('tabs:reload-active'),
  openActiveDevTools: () => ipcRenderer.invoke('tabs:open-active-devtools'),
  openActiveInBrowser: () => ipcRenderer.invoke('tabs:open-active-in-browser'),
  onChanged: (callback) => {
    const listener = (_event, state) => callback(state)
    ipcRenderer.on('tabs:changed', listener)
    return () => ipcRenderer.removeListener('tabs:changed', listener)
  },
  window: {
    minimize: () => ipcRenderer.invoke('window:minimize'),
    toggleMaximize: () => ipcRenderer.invoke('window:toggle-maximize'),
    close: () => ipcRenderer.invoke('window:close'),
  },
  platform: process.platform,
})

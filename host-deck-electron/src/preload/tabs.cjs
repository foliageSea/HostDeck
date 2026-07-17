const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('hostDeckTabs', {
  list: () => ipcRenderer.invoke('tabs:list'),
  create: () => ipcRenderer.invoke('tabs:create'),
  activate: (id) => ipcRenderer.invoke('tabs:activate', id),
  close: (id) => ipcRenderer.invoke('tabs:close', id),
  rename: (id, title) => ipcRenderer.invoke('tabs:rename', id, title),
  reorder: (id, targetId, placement) => ipcRenderer.invoke('tabs:reorder', id, targetId, placement),
  setBarPosition: (position) => ipcRenderer.invoke('tabs:set-bar-position', position),
  setContentVisible: (visible) => ipcRenderer.invoke('tabs:set-content-visible', visible),
  suspendContent: () => ipcRenderer.invoke('tabs:suspend-content'),
  setSidebarWidth: (width) => ipcRenderer.invoke('tabs:set-sidebar-width', width),
  reloadActive: () => ipcRenderer.invoke('tabs:reload-active'),
  openActiveDevTools: () => ipcRenderer.invoke('tabs:open-active-devtools'),
  openActiveInBrowser: () => ipcRenderer.invoke('tabs:open-active-in-browser'),
  onChanged: (callback) => {
    const listener = (_event, state) => callback(state)
    ipcRenderer.on('tabs:changed', listener)
    return () => ipcRenderer.removeListener('tabs:changed', listener)
  },
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
  },
  platform: process.platform
})

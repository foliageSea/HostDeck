import { markRaw, type Component } from 'vue'
import { defineStore } from 'pinia'
import { useSshStore } from '@/stores/ssh'
import type { AppIconKey, DesktopAppId } from '@/types/desktop'
import DashboardView from '@/views/Dashboard/index.vue'
import DockerView from '@/views/Docker/index.vue'
import FilesView from '@/views/Files/index.vue'
import MediaViewerView from '@/views/MediaViewer/index.vue'
import SettingsView from '@/views/Settings/index.vue'
import TerminalView from '@/views/Terminal/index.vue'
import TextEditorView from '@/views/TextEditor/index.vue'

export interface AppConfig {
  id: DesktopAppId
  title: string
  icon: AppIconKey
  component: Component
  width?: number
  height?: number
  hide?: boolean
}

export interface WindowState {
  id: string
  appId: DesktopAppId
  title: string
  component: Component
  icon: AppIconKey
  x: number
  y: number
  width: number
  height: number
  isMinimized: boolean
  isMaximized: boolean
  zIndex: number
  props?: Record<string, unknown>
}

export const useDesktopStore = defineStore('desktop', {
  state: () => ({
    activeWindowId: null as string | null,
    apps: {
      dashboard: {
        component: markRaw(DashboardView),
        height: 540,
        icon: 'dashboard',
        id: 'dashboard',
        title: '系统监控',
        width: 420,
      },
      docker: {
        component: markRaw(DockerView),
        height: 760,
        icon: 'docker',
        id: 'docker',
        title: 'Docker 管理',
        width: 1180,
      },
      files: {
        component: markRaw(FilesView),
        height: 720,
        icon: 'folder',
        id: 'files',
        title: '文件管理',
        width: 1080,
      },
      editor: {
        component: markRaw(TextEditorView),
        height: 720,
        hide: true,
        icon: 'editor',
        id: 'editor',
        title: '文本编辑器',
        width: 980,
      },
      logout: {
        component: markRaw({ render: () => null }),
        height: 0,
        icon: 'logout',
        id: 'logout',
        title: '断开连接',
        width: 0,
      },
      'media-viewer': {
        component: markRaw(MediaViewerView),
        height: 760,
        hide: true,
        icon: 'media',
        id: 'media-viewer',
        title: '媒体预览',
        width: 1080,
      },
      settings: {
        component: markRaw(SettingsView),
        height: 520,
        icon: 'settings',
        id: 'settings',
        title: '设置',
        width: 480,
      },
      terminal: {
        component: markRaw(TerminalView),
        height: 560,
        icon: 'terminal',
        id: 'terminal',
        title: '终端',
        width: 920,
      },
    } as Record<DesktopAppId, AppConfig>,
    nextZIndex: 100,
    windows: [] as WindowState[],
  }),

  actions: {
    closeAppWindows(appId: DesktopAppId) {
      this.windows = this.windows.filter((window) => window.appId !== appId)

      if (this.activeWindowId && !this.windows.some((window) => window.id === this.activeWindowId)) {
        const nextActiveWindow = [...this.windows].sort((left, right) => right.zIndex - left.zIndex)[0]
        this.activeWindowId = nextActiveWindow?.id ?? null
      }
    },

    closeWindow(id: string) {
      const targetIndex = this.windows.findIndex((window) => window.id === id)
      if (targetIndex === -1) {
        return
      }

      this.windows.splice(targetIndex, 1)

      if (this.activeWindowId === id) {
        const nextActiveWindow = [...this.windows].sort((left, right) => right.zIndex - left.zIndex)[0]
        this.activeWindowId = nextActiveWindow?.id ?? null
      }
    },

    focusWindow(id: string) {
      const targetWindow = this.windows.find((window) => window.id === id)
      if (!targetWindow) {
        return
      }

      if (targetWindow.isMinimized) {
        targetWindow.isMinimized = false
      }

      targetWindow.zIndex = this.nextZIndex++
      this.activeWindowId = id
    },

    maximizeWindow(id: string) {
      const targetWindow = this.windows.find((window) => window.id === id)
      if (!targetWindow) {
        return
      }

      targetWindow.isMaximized = !targetWindow.isMaximized
      this.focusWindow(id)
    },

    minimizeWindow(id: string) {
      const targetWindow = this.windows.find((window) => window.id === id)
      if (!targetWindow) {
        return
      }

      targetWindow.isMinimized = true
      if (this.activeWindowId === id) {
        this.activeWindowId = null
      }
    },

    openWindow(appId: DesktopAppId, props?: Record<string, unknown>) {
      if (appId === 'logout') {
        useSshStore().clearSession()
        this.windows = []
        this.activeWindowId = null
        return
      }

      const app = this.apps[appId]
      if (!app) {
        return
      }

      const windowId = `${appId}-${Date.now()}`
      const windowState: WindowState = {
        appId,
        component: app.component,
        height: app.height ?? 600,
        icon: app.icon,
        id: windowId,
        isMaximized: false,
        isMinimized: false,
        props,
        title: typeof props?.title === 'string' ? props.title : app.title,
        width: app.width ?? 800,
        x: 80 + this.windows.length * 24,
        y: 72 + this.windows.length * 24,
        zIndex: this.nextZIndex++,
      }

      this.windows.push(windowState)
      this.activeWindowId = windowId
    },

    reset() {
      this.windows = []
      this.activeWindowId = null
      this.nextZIndex = 100
    },

    restoreWindow(id: string) {
      const targetWindow = this.windows.find((window) => window.id === id)
      if (!targetWindow) {
        return
      }

      targetWindow.isMinimized = false
      this.focusWindow(id)
    },

    updateWindowPosition(id: string, x: number, y: number) {
      const targetWindow = this.windows.find((window) => window.id === id)
      if (!targetWindow) {
        return
      }

      targetWindow.x = x
      targetWindow.y = y
    },

    updateWindowSize(id: string, width: number, height: number) {
      const targetWindow = this.windows.find((window) => window.id === id)
      if (!targetWindow) {
        return
      }

      targetWindow.width = width
      targetWindow.height = height
    },
  },
})

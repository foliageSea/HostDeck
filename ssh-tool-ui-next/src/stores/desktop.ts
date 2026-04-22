import { markRaw, type Component } from 'vue'
import { defineStore } from 'pinia'
import { getUiApi } from '@/lib/ui'
import { useSshStore } from '@/stores/ssh'
import { useWindowSessionStore } from '@/stores/window-session'
import type { AppIconKey, DesktopAppId } from '@/types/desktop'
import { basename, normalize } from '@/utils/path'
import DashboardView from '@/views/Dashboard/index.vue'
import DockerView from '@/views/Docker/index.vue'
import FilesView from '@/views/Files/index.vue'
import MediaViewerView from '@/views/MediaViewer/index.vue'
import RuntimeSessionsView from '@/views/RuntimeSessions/index.vue'
import SettingsView from '@/views/Settings/index.vue'
import TerminalView from '@/views/Terminal/index.vue'
import TextEditorView from '@/views/TextEditor/index.vue'

export const maxSessionWindows = 8

const PINNED_DIRECTORIES_STORAGE_KEY = 'ssh-tool:desktop:pinned-directories'
const PINNED_DIRECTORY_POSITIONS_STORAGE_KEY = 'ssh-tool:desktop:pinned-directory-positions'

const sessionWindowAppIds = new Set<DesktopAppId>(['terminal'])

type PinnedDirectoriesByConnection = Record<string, string[]>
type PinnedDirectoryPositions = Record<string, {
  x: number
  y: number
}>
type PinnedDirectoryPositionsByConnection = Record<string, PinnedDirectoryPositions>

function normalizePinnedDirectoriesRecord(value: unknown): PinnedDirectoriesByConnection {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {}
  }

  return Object.fromEntries(
    Object.entries(value).map(([key, paths]) => [
      key,
      Array.isArray(paths)
        ? Array.from(new Set(paths.filter((path): path is string => typeof path === 'string').map((path) => normalize(path))))
        : [],
    ]),
  )
}

function loadPinnedDirectories(): PinnedDirectoriesByConnection {
  if (typeof window === 'undefined') {
    return {}
  }

  try {
    const rawValue = window.localStorage.getItem(PINNED_DIRECTORIES_STORAGE_KEY)
    if (!rawValue) {
      return {}
    }

    return normalizePinnedDirectoriesRecord(JSON.parse(rawValue))
  } catch {
    return {}
  }
}

function normalizePinnedDirectoryPositionsRecord(value: unknown): PinnedDirectoryPositionsByConnection {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {}
  }

  return Object.fromEntries(
    Object.entries(value).map(([connectionKey, positions]) => {
      if (!positions || typeof positions !== 'object' || Array.isArray(positions)) {
        return [connectionKey, {}]
      }

      return [
        connectionKey,
        Object.fromEntries(
          Object.entries(positions)
            .filter(([path, position]) => {
              if (typeof path !== 'string' || !position || typeof position !== 'object' || Array.isArray(position)) {
                return false
              }

              const x = 'x' in position ? position.x : null
              const y = 'y' in position ? position.y : null
              return Number.isFinite(x) && Number.isFinite(y)
            })
            .map(([path, position]) => {
              const nextPosition = position as { x: number; y: number }

              return [
                normalize(path),
                {
                  x: Math.round(nextPosition.x),
                  y: Math.round(nextPosition.y),
                },
              ]
            }),
        ),
      ]
    }),
  )
}

function loadPinnedDirectoryPositions(): PinnedDirectoryPositionsByConnection {
  if (typeof window === 'undefined') {
    return {}
  }

  try {
    const rawValue = window.localStorage.getItem(PINNED_DIRECTORY_POSITIONS_STORAGE_KEY)
    if (!rawValue) {
      return {}
    }

    return normalizePinnedDirectoryPositionsRecord(JSON.parse(rawValue))
  } catch {
    return {}
  }
}

function persistPinnedDirectories(value: PinnedDirectoriesByConnection) {
  if (typeof window === 'undefined') {
    return
  }

  window.localStorage.setItem(PINNED_DIRECTORIES_STORAGE_KEY, JSON.stringify(value))
}

function persistPinnedDirectoryPositions(value: PinnedDirectoryPositionsByConnection) {
  if (typeof window === 'undefined') {
    return
  }

  window.localStorage.setItem(PINNED_DIRECTORY_POSITIONS_STORAGE_KEY, JSON.stringify(value))
}

function getPinnedDirectoryConnectionKey() {
  const sshStore = useSshStore()
  const host = sshStore.host.trim()
  const username = sshStore.username.trim()
  const port = sshStore.port

  if (!host || !username || port === null) {
    return null
  }

  return `${username}@${host}:${port}`
}

function formatPinnedDirectoryTitle(path: string) {
  return path === '/' ? '文件管理 · 根目录' : `文件管理 · ${basename(path)}`
}

function isSessionWindowAppId(appId: DesktopAppId) {
  return sessionWindowAppIds.has(appId)
}

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

function getTopVisibleWindow(windows: WindowState[]) {
  return [...windows]
    .filter((window) => !window.isMinimized)
    .sort((left, right) => right.zIndex - left.zIndex)[0]
}

export const useDesktopStore = defineStore('desktop', {
  state: () => ({
    activeWindowId: null as string | null,
    apps: {
      terminal: {
        component: markRaw(TerminalView),
        height: 560,
        icon: 'terminal',
        id: 'terminal',
        title: '终端',
        width: 920,
      },
      dashboard: {
        component: markRaw(DashboardView),
        height: 540,
        icon: 'dashboard',
        id: 'dashboard',
        title: '系统监控',
        width: 420,
        hide: true,
      },
      files: {
        component: markRaw(FilesView),
        height: 720,
        icon: 'folder',
        id: 'files',
        title: '文件管理',
        width: 1280,
      },
      docker: {
        component: markRaw(DockerView),
        height: 760,
        icon: 'docker',
        id: 'docker',
        title: 'Docker 管理',
        width: 1180,
        hide: false,
      },
      'runtime-sessions': {
        component: markRaw(RuntimeSessionsView),
        height: 720,
        icon: 'runtime',
        id: 'runtime-sessions',
        title: '运行态会话',
        width: 1120,
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
        hide: true,
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
        height: 600,
        icon: 'settings',
        id: 'settings',
        title: '设置',
        width: 480,
      },

    } as Record<DesktopAppId, AppConfig>,
    nextZIndex: 100,
    pinnedDirectoriesByConnection: loadPinnedDirectories() as PinnedDirectoriesByConnection,
    pinnedDirectoryPositionsByConnection: loadPinnedDirectoryPositions() as PinnedDirectoryPositionsByConnection,
    windows: [] as WindowState[],
  }),

  getters: {
    sessionWindowCount: (state): number => state.windows.filter((window) => isSessionWindowAppId(window.appId)).length,
  },

  actions: {
    canOpenWindow(appId: DesktopAppId) {
      return !isSessionWindowAppId(appId) || this.sessionWindowCount < maxSessionWindows
    },

    getPinnedDirectories() {
      const connectionKey = getPinnedDirectoryConnectionKey()
      return connectionKey ? this.pinnedDirectoriesByConnection[connectionKey] ?? [] : []
    },

    getPinnedDirectoryPositions() {
      const connectionKey = getPinnedDirectoryConnectionKey()
      return connectionKey ? this.pinnedDirectoryPositionsByConnection[connectionKey] ?? {} : {}
    },

    isDirectoryPinned(path: string) {
      return this.getPinnedDirectories().includes(normalize(path))
    },

    openPinnedDirectory(path: string) {
      const targetPath = normalize(path)
      this.openWindow('files', {
        path: targetPath,
        title: formatPinnedDirectoryTitle(targetPath),
      })
    },

    pinDirectoryToDesktop(path: string) {
      const targetPath = normalize(path)
      if (this.isDirectoryPinned(targetPath)) {
        return false
      }

      this.setPinnedDirectories([...this.getPinnedDirectories(), targetPath])
      return true
    },

    setPinnedDirectories(paths: string[]) {
      const connectionKey = getPinnedDirectoryConnectionKey()
      if (!connectionKey) {
        return
      }

      const normalizedPaths = Array.from(
        new Set(paths.map((path) => normalize(path))),
      )
      const nextPinnedDirectories = { ...this.pinnedDirectoriesByConnection }
      const nextPinnedDirectoryPositions = { ...this.pinnedDirectoryPositionsByConnection }
      const currentPositions = this.pinnedDirectoryPositionsByConnection[connectionKey] ?? {}
      const retainedPositions = Object.fromEntries(
        Object.entries(currentPositions).filter(([path]) => normalizedPaths.includes(path)),
      )

      if (normalizedPaths.length === 0) {
        delete nextPinnedDirectories[connectionKey]
        delete nextPinnedDirectoryPositions[connectionKey]
      } else {
        nextPinnedDirectories[connectionKey] = normalizedPaths
        if (Object.keys(retainedPositions).length > 0) {
          nextPinnedDirectoryPositions[connectionKey] = retainedPositions
        } else {
          delete nextPinnedDirectoryPositions[connectionKey]
        }
      }

      this.pinnedDirectoriesByConnection = nextPinnedDirectories
      this.pinnedDirectoryPositionsByConnection = nextPinnedDirectoryPositions
      persistPinnedDirectories(nextPinnedDirectories)
      persistPinnedDirectoryPositions(nextPinnedDirectoryPositions)
    },

    setPinnedDirectoryPosition(path: string, x: number, y: number) {
      const connectionKey = getPinnedDirectoryConnectionKey()
      if (!connectionKey || !this.isDirectoryPinned(path)) {
        return
      }

      const targetPath = normalize(path)
      const nextPinnedDirectoryPositions = {
        ...this.pinnedDirectoryPositionsByConnection,
        [connectionKey]: {
          ...(this.pinnedDirectoryPositionsByConnection[connectionKey] ?? {}),
          [targetPath]: {
            x: Math.round(x),
            y: Math.round(y),
          },
        },
      }

      this.pinnedDirectoryPositionsByConnection = nextPinnedDirectoryPositions
      persistPinnedDirectoryPositions(nextPinnedDirectoryPositions)
    },

    toggleDirectoryPin(path: string) {
      const targetPath = normalize(path)
      if (this.isDirectoryPinned(targetPath)) {
        this.unpinDirectoryFromDesktop(targetPath)
        return false
      }

      this.pinDirectoryToDesktop(targetPath)
      return true
    },

    unpinDirectoryFromDesktop(paths: string | string[]) {
      const targetPaths = new Set((Array.isArray(paths) ? paths : [paths]).map((path) => normalize(path)))
      this.setPinnedDirectories(this.getPinnedDirectories().filter((path) => !targetPaths.has(path)))
    },

    closeAppWindows(appId: DesktopAppId) {
      const closedWindowIds = this.windows.filter((window) => window.appId === appId).map((window) => window.id)
      const windowSessionStore = useWindowSessionStore()

      this.windows = this.windows.filter((window) => window.appId !== appId)
      closedWindowIds.forEach((windowId) => {
        void windowSessionStore.disconnectWindow(windowId)
      })

      if (this.activeWindowId && !this.windows.some((window) => window.id === this.activeWindowId)) {
        const nextActiveWindow = getTopVisibleWindow(this.windows)
        this.activeWindowId = nextActiveWindow?.id ?? null
      }
    },

    closeWindow(id: string) {
      const targetIndex = this.windows.findIndex((window) => window.id === id)
      if (targetIndex === -1) {
        return
      }

      this.windows.splice(targetIndex, 1)
      void useWindowSessionStore().disconnectWindow(id)

      if (this.activeWindowId === id) {
        const nextActiveWindow = getTopVisibleWindow(this.windows)
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
        const nextActiveWindow = getTopVisibleWindow(this.windows)
        this.activeWindowId = nextActiveWindow?.id ?? null
      }
    },

    openWindow(appId: DesktopAppId, props?: Record<string, unknown>) {
      if (appId === 'logout') {
        void useSshStore().clearSession()
        this.windows = []
        this.activeWindowId = null
        return
      }

      const app = this.apps[appId]
      if (!app) {
        return
      }

      if (!this.canOpenWindow(appId)) {
        getUiApi().message.warning(`最多只能打开 ${maxSessionWindows} 个会话窗口。`)
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
      const windowSessionStore = useWindowSessionStore()
      this.windows.forEach((window) => {
        void windowSessionStore.disconnectWindow(window.id)
      })
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

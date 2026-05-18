import { markRaw, type Component } from 'vue'
import { defineStore } from 'pinia'
import { getUiApi } from '@/lib/ui'
import { useSshStore } from '@/stores/ssh'
import { useWindowSessionStore } from '@/stores/window-session'
import type { AppIconKey, DesktopAppId } from '@/types/desktop'
import { basename, normalize } from '@/utils/path'
import DashboardView from '@/views/Dashboard/index.vue'
import DockerCreateComposeView from '@/views/Docker/components/DockerCreateComposeView.vue'
import DockerCreateContainerView from '@/views/Docker/components/DockerCreateContainerView.vue'
import DockerComposeServicesView from '@/views/Docker/components/DockerComposeServicesView.vue'
import DockerView from '@/views/Docker/index.vue'
import FilesView from '@/views/Files/index.vue'
import MediaViewerView from '@/views/MediaViewer/index.vue'
import RuntimeSessionsView from '@/views/RuntimeSessions/index.vue'
import SettingsView from '@/views/Settings/index.vue'
import TerminalView from '@/views/Terminal/index.vue'
import TextEditorView from '@/views/TextEditor/index.vue'

export const maxSessionWindows = 8
const windowCloseAnimationMs = 220

const PINNED_DIRECTORIES_STORAGE_KEY = 'ssh-tool:desktop:pinned-directories'
const PINNED_DIRECTORY_POSITIONS_STORAGE_KEY = 'ssh-tool:desktop:pinned-directory-positions'
const PINNED_PORT_LINKS_STORAGE_KEY = 'ssh-tool:desktop:pinned-port-links'
const PINNED_PORT_LINK_POSITIONS_STORAGE_KEY = 'ssh-tool:desktop:pinned-port-link-positions'

const sessionWindowAppIds = new Set<DesktopAppId>(['terminal'])

type PinnedDirectoriesByConnection = Record<string, string[]>
type PinnedDirectoryPositions = Record<string, {
  x: number
  y: number
}>
type WindowBeforeCloseHandler = () => boolean | Promise<boolean>
type PinnedDirectoryPositionsByConnection = Record<string, PinnedDirectoryPositions>

export interface PinnedPortLink {
  host: string
  id: string
  label: string
  port: string
  portText: string
  url: string
}

type PinnedPortLinksByConnection = Record<string, PinnedPortLink[]>
type PinnedPortLinkPositionsByConnection = Record<string, PinnedDirectoryPositions>

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

function normalizePinnedPortLinksRecord(value: unknown): PinnedPortLinksByConnection {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {}
  }

  return Object.fromEntries(
    Object.entries(value).map(([key, links]) => [
      key,
      Array.isArray(links)
        ? links
            .filter((link): link is PinnedPortLink => {
              if (!link || typeof link !== 'object' || Array.isArray(link)) {
                return false
              }

              const candidate = link as Partial<PinnedPortLink>
              return typeof candidate.id === 'string' && typeof candidate.label === 'string' && typeof candidate.url === 'string'
            })
            .map((link) => ({
              host: typeof link.host === 'string' ? link.host : '',
              id: link.id,
              label: link.label,
              port: typeof link.port === 'string' ? link.port : '',
              portText: typeof link.portText === 'string' ? link.portText : link.url,
              url: link.url,
            }))
        : [],
    ]),
  )
}

function loadPinnedPortLinks(): PinnedPortLinksByConnection {
  if (typeof window === 'undefined') {
    return {}
  }

  try {
    const rawValue = window.localStorage.getItem(PINNED_PORT_LINKS_STORAGE_KEY)
    if (!rawValue) {
      return {}
    }

    return normalizePinnedPortLinksRecord(JSON.parse(rawValue))
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

function loadPinnedPortLinkPositions(): PinnedPortLinkPositionsByConnection {
  if (typeof window === 'undefined') {
    return {}
  }

  try {
    const rawValue = window.localStorage.getItem(PINNED_PORT_LINK_POSITIONS_STORAGE_KEY)
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

function persistPinnedPortLinks(value: PinnedPortLinksByConnection) {
  if (typeof window === 'undefined') {
    return
  }

  window.localStorage.setItem(PINNED_PORT_LINKS_STORAGE_KEY, JSON.stringify(value))
}

function persistPinnedPortLinkPositions(value: PinnedPortLinkPositionsByConnection) {
  if (typeof window === 'undefined') {
    return
  }

  window.localStorage.setItem(PINNED_PORT_LINK_POSITIONS_STORAGE_KEY, JSON.stringify(value))
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
  minWidth?: number
  minHeight?: number
  minimizable?: boolean
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
  minWidth: number
  minHeight: number
  minimizable: boolean
  isMinimized: boolean
  isMaximized: boolean
  zIndex: number
  isClosing: boolean
  beforeClose?: WindowBeforeCloseHandler
  props?: Record<string, unknown>
}

function getTopVisibleWindow(windows: WindowState[]) {
  return [...windows]
    .filter((window) => !window.isMinimized && !window.isClosing)
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
        minHeight: 360,
        minWidth: 640,
        title: '终端',
        width: 920,
      },
      dashboard: {
        component: markRaw(DashboardView),
        height: 760,
        icon: 'dashboard',
        id: 'dashboard',
        minHeight: 620,
        minWidth: 880,
        title: '性能监控',
        width: 1180,
        hide: false,
      },
      files: {
        component: markRaw(FilesView),
        height: 720,
        icon: 'folder',
        id: 'files',
        minHeight: 560,
        minWidth: 900,
        title: '文件管理',
        width: 1280,
      },
      docker: {
        component: markRaw(DockerView),
        height: 760,
        icon: 'docker',
        id: 'docker',
        minHeight: 560,
        minWidth: 900,
        title: 'Docker 管理',
        width: 1180,
        hide: false,
      },
      'docker-create-container': {
        component: markRaw(DockerCreateContainerView),
        height: 700,
        hide: true,
        icon: 'docker',
        id: 'docker-create-container',
        minimizable: false,
        minHeight: 560,
        minWidth: 720,
        title: '新建容器',
        width: 820,
      },
      'docker-create-compose': {
        component: markRaw(DockerCreateComposeView),
        height: 720,
        hide: true,
        icon: 'docker',
        id: 'docker-create-compose',
        minimizable: false,
        minHeight: 560,
        minWidth: 760,
        title: '新建编排',
        width: 860,
      },
      'docker-compose-services': {
        component: markRaw(DockerComposeServicesView),
        height: 680,
        hide: true,
        icon: 'docker',
        id: 'docker-compose-services',
        minimizable: false,
        minHeight: 480,
        minWidth: 760,
        title: '编排服务',
        width: 960,
      },
      'runtime-sessions': {
        component: markRaw(RuntimeSessionsView),
        height: 720,
        icon: 'runtime',
        id: 'runtime-sessions',
        minHeight: 520,
        minWidth: 860,
        title: '运行态会话',
        width: 1120,
      },
      editor: {
        component: markRaw(TextEditorView),
        height: 720,
        hide: true,
        icon: 'editor',
        id: 'editor',
        minimizable: false,
        minHeight: 480,
        minWidth: 720,
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
        minimizable: false,
        minHeight: 480,
        minWidth: 720,
        title: '媒体预览',
        width: 1080,
      },
      settings: {
        component: markRaw(SettingsView),
        height: 600,
        icon: 'settings',
        id: 'settings',
        minHeight: 460,
        minWidth: 420,
        title: '设置',
        width: 480,
      },

    } as Record<DesktopAppId, AppConfig>,
    nextZIndex: 100,
    pinnedDirectoriesByConnection: loadPinnedDirectories() as PinnedDirectoriesByConnection,
    pinnedDirectoryPositionsByConnection: loadPinnedDirectoryPositions() as PinnedDirectoryPositionsByConnection,
    pinnedPortLinkPositionsByConnection: loadPinnedPortLinkPositions() as PinnedPortLinkPositionsByConnection,
    pinnedPortLinksByConnection: loadPinnedPortLinks() as PinnedPortLinksByConnection,
    windows: [] as WindowState[],
  }),

  getters: {
    sessionWindowCount: (state): number => state.windows.filter((window) => isSessionWindowAppId(window.appId) && !window.isClosing).length,
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

    getPinnedPortLinkPositions() {
      const connectionKey = getPinnedDirectoryConnectionKey()
      return connectionKey ? this.pinnedPortLinkPositionsByConnection[connectionKey] ?? {} : {}
    },

    getPinnedPortLinks() {
      const connectionKey = getPinnedDirectoryConnectionKey()
      return connectionKey ? this.pinnedPortLinksByConnection[connectionKey] ?? [] : []
    },

    isDirectoryPinned(path: string) {
      return this.getPinnedDirectories().includes(normalize(path))
    },

    isPortLinkPinned(url: string) {
      return this.getPinnedPortLinks().some((link) => link.url === url)
    },

    openPinnedDirectory(path: string) {
      const targetPath = normalize(path)
      this.openWindow('files', {
        path: targetPath,
        title: formatPinnedDirectoryTitle(targetPath),
      })
    },

    openPinnedPortLink(id: string) {
      const link = this.getPinnedPortLinks().find((item) => item.id === id)
      if (!link) {
        return
      }

      window.open(link.url, '_blank', 'noopener')
    },

    pinDirectoryToDesktop(path: string) {
      const targetPath = normalize(path)
      if (this.isDirectoryPinned(targetPath)) {
        return false
      }

      this.setPinnedDirectories([...this.getPinnedDirectories(), targetPath])
      return true
    },

    pinPortLinkToDesktop(link: PinnedPortLink) {
      const connectionKey = getPinnedDirectoryConnectionKey()
      if (!connectionKey) {
        return false
      }

      const currentLinks = this.pinnedPortLinksByConnection[connectionKey] ?? []
      if (currentLinks.some((item) => item.url === link.url)) {
        return false
      }

      const nextPinnedPortLinks = {
        ...this.pinnedPortLinksByConnection,
        [connectionKey]: [...currentLinks, link],
      }
      this.pinnedPortLinksByConnection = nextPinnedPortLinks
      persistPinnedPortLinks(nextPinnedPortLinks)
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

    setPinnedPortLinkPosition(id: string, x: number, y: number) {
      const connectionKey = getPinnedDirectoryConnectionKey()
      if (!connectionKey || !this.getPinnedPortLinks().some((link) => link.id === id)) {
        return
      }

      const nextPinnedPortLinkPositions = {
        ...this.pinnedPortLinkPositionsByConnection,
        [connectionKey]: {
          ...(this.pinnedPortLinkPositionsByConnection[connectionKey] ?? {}),
          [id]: {
            x: Math.round(x),
            y: Math.round(y),
          },
        },
      }

      this.pinnedPortLinkPositionsByConnection = nextPinnedPortLinkPositions
      persistPinnedPortLinkPositions(nextPinnedPortLinkPositions)
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

    togglePortLinkPin(link: PinnedPortLink) {
      if (this.isPortLinkPinned(link.url)) {
        this.unpinPortLinkFromDesktop(this.getPinnedPortLinks().filter((item) => item.url === link.url).map((item) => item.id))
        return false
      }

      this.pinPortLinkToDesktop(link)
      return true
    },

    unpinDirectoryFromDesktop(paths: string | string[]) {
      const targetPaths = new Set((Array.isArray(paths) ? paths : [paths]).map((path) => normalize(path)))
      this.setPinnedDirectories(this.getPinnedDirectories().filter((path) => !targetPaths.has(path)))
    },

    unpinPortLinkFromDesktop(ids: string | string[]) {
      const connectionKey = getPinnedDirectoryConnectionKey()
      if (!connectionKey) {
        return
      }

      const targetIds = new Set(Array.isArray(ids) ? ids : [ids])
      const nextLinks = this.getPinnedPortLinks().filter((link) => !targetIds.has(link.id))
      const nextPinnedPortLinks = { ...this.pinnedPortLinksByConnection }
      const nextPinnedPortLinkPositions = { ...this.pinnedPortLinkPositionsByConnection }
      const retainedPositions = Object.fromEntries(
        Object.entries(nextPinnedPortLinkPositions[connectionKey] ?? {}).filter(([id]) => !targetIds.has(id)),
      )

      if (nextLinks.length === 0) {
        delete nextPinnedPortLinks[connectionKey]
        delete nextPinnedPortLinkPositions[connectionKey]
      } else {
        nextPinnedPortLinks[connectionKey] = nextLinks
        if (Object.keys(retainedPositions).length > 0) {
          nextPinnedPortLinkPositions[connectionKey] = retainedPositions
        } else {
          delete nextPinnedPortLinkPositions[connectionKey]
        }
      }

      this.pinnedPortLinksByConnection = nextPinnedPortLinks
      this.pinnedPortLinkPositionsByConnection = nextPinnedPortLinkPositions
      persistPinnedPortLinks(nextPinnedPortLinks)
      persistPinnedPortLinkPositions(nextPinnedPortLinkPositions)
    },

    closeAppWindows(appId: DesktopAppId) {
      this.windows
        .filter((window) => window.appId === appId)
        .forEach((window) => {
          void this.requestCloseWindow(window.id)
        })
    },

    async requestCloseWindow(id: string) {
      const targetWindow = this.windows.find((window) => window.id === id)
      if (!targetWindow || targetWindow.isClosing) {
        return
      }

      if (targetWindow.beforeClose) {
        const canClose = await targetWindow.beforeClose()
        if (!canClose) {
          return
        }
      }

      this.closeWindow(id)
    },

    closeWindow(id: string) {
      const targetIndex = this.windows.findIndex((window) => window.id === id)
      if (targetIndex === -1) {
        return
      }

      const targetWindow = this.windows[targetIndex]
      if (targetWindow.isClosing) {
        return
      }

      targetWindow.isClosing = true

      if (this.activeWindowId === id) {
        const nextActiveWindow = getTopVisibleWindow(this.windows)
        this.activeWindowId = nextActiveWindow?.id ?? null
      }

      globalThis.setTimeout(() => {
        const removingIndex = this.windows.findIndex((window) => window.id === id)
        if (removingIndex === -1) {
          return
        }

        this.windows.splice(removingIndex, 1)
        void useWindowSessionStore().disconnectWindow(id)

        if (this.activeWindowId === id) {
          const nextActiveWindow = getTopVisibleWindow(this.windows)
          this.activeWindowId = nextActiveWindow?.id ?? null
        }
      }, windowCloseAnimationMs)
    },

    focusWindow(id: string) {
      const targetWindow = this.windows.find((window) => window.id === id)
      if (!targetWindow || targetWindow.isClosing) {
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
      if (!targetWindow || targetWindow.isClosing) {
        return
      }

      targetWindow.isMaximized = !targetWindow.isMaximized
      this.focusWindow(id)
    },

    minimizeWindow(id: string) {
      const targetWindow = this.windows.find((window) => window.id === id)
      if (!targetWindow || targetWindow.isClosing || !targetWindow.minimizable) {
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
      const minWidth = app.minWidth ?? 320
      const minHeight = app.minHeight ?? 240
      const windowState: WindowState = {
        appId,
        component: app.component,
        height: Math.max(app.height ?? 600, minHeight),
        icon: app.icon,
        isClosing: false,
        id: windowId,
        isMaximized: false,
        isMinimized: false,
        minimizable: app.minimizable ?? true,
        minHeight,
        minWidth,
        props,
        title: typeof props?.title === 'string' ? props.title : app.title,
        width: Math.max(app.width ?? 800, minWidth),
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

    setWindowBeforeClose(id: string, handler?: WindowBeforeCloseHandler) {
      const targetWindow = this.windows.find((window) => window.id === id)
      if (!targetWindow) {
        return
      }

      targetWindow.beforeClose = handler
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

      targetWindow.width = Math.max(targetWindow.minWidth, width)
      targetWindow.height = Math.max(targetWindow.minHeight, height)
    },
  },
})

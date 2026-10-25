import { computed, markRaw, onScopeDispose, ref, toRef } from 'vue'
import { defineStore } from 'pinia'
import { createDesktop, type OpenWindowOptions } from '@host-deck/webos'
import { getUiApi } from '@/lib/ui'
import {
  createHostDesktopApps,
  defaultDockAppIds,
  maxSessionWindows,
  sessionWindowAppIds,
} from '@/lib/host-desktop-apps'
import { useSshStore } from '@/stores/ssh'
import { useSettingsStore } from '@/stores/settings'
import { useWindowSessionStore } from '@/stores/window-session'
import type { DesktopAppId } from '@/types/desktop'
import { basename, normalize } from '@/utils/path'

export { defaultDockAppIds, maxSessionWindows }
export type { AppConfig, OpenWindowOptions, WindowState } from '@host-deck/webos'
export const DOCK_APPS_STORAGE_KEY = 'host-deck:desktop:dock-apps'
export const DOCK_AI_AGENT_MIGRATION_KEY = 'host-deck:desktop:dock-ai-agent-v1'
const directoryKey = 'host-deck:desktop:pinned-directories'
const directoryPositionsKey = 'host-deck:desktop:pinned-directory-positions'
const portLinksKey = 'host-deck:desktop:pinned-port-links'
const portPositionsKey = 'host-deck:desktop:pinned-port-link-positions'
type Positions = Record<string, { x: number; y: number }>
type PositionsByConnection = Record<string, Positions>
export interface PinnedPortLink {
  host: string
  id: string
  label: string
  port: string
  portText: string
  url: string
}

function loadRecord(key: string): Record<string, unknown> {
  try {
    const value: unknown = JSON.parse(window.localStorage.getItem(key) ?? '{}')
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {}
  } catch {
    return {}
  }
}

function loadPositions(key: string): PositionsByConnection {
  return Object.fromEntries(
    Object.entries(loadRecord(key)).map(([connection, value]) => [
      connection,
      value && typeof value === 'object' && !Array.isArray(value)
        ? Object.fromEntries(
            Object.entries(value)
              .filter(
                ([, position]) =>
                  position && Number.isFinite(position.x) && Number.isFinite(position.y),
              )
              .map(([id, position]) => [
                id,
                { x: Math.round(position.x), y: Math.round(position.y) },
              ]),
          )
        : {},
    ]),
  )
}

function persist(key: string, value: unknown) {
  try {
    window.localStorage.setItem(key, JSON.stringify(value))
  } catch {
    /* Local persistence is best effort. */
  }
}

function migrateDock(apps: ReturnType<typeof createHostDesktopApps>) {
  try {
    const saved: unknown = JSON.parse(window.localStorage.getItem(DOCK_APPS_STORAGE_KEY) ?? 'null')
    if (!Array.isArray(saved)) {
      window.localStorage.setItem(DOCK_AI_AGENT_MIGRATION_KEY, 'done')
      return
    }
    // OpenCode has been removed; keep its old slot for the app that replaced it.
    const legacyIndex = saved.indexOf('opencode')
    const available = new Set(apps.filter((app) => app.showInLaunchpad).map((app) => app.id))
    const ids = Array.from(
      new Set(saved.filter((id): id is string => typeof id === 'string' && available.has(id))),
    )
    if (saved.length && !ids.length) ids.push(...defaultDockAppIds)
    if (
      ids.length &&
      !ids.includes('ai-agent') &&
      window.localStorage.getItem(DOCK_AI_AGENT_MIGRATION_KEY) !== 'done'
    ) {
      ids.splice(legacyIndex < 0 ? ids.length : Math.min(legacyIndex, ids.length), 0, 'ai-agent')
    }
    persist(DOCK_APPS_STORAGE_KEY, ids)
    window.localStorage.setItem(DOCK_AI_AGENT_MIGRATION_KEY, 'done')
  } catch {
    /* The package falls back to the default Dock. */
  }
}

/** Compatibility facade: window operations belong to WebOS, remote shortcuts belong to HostDeck. */
export const useDesktopStore = defineStore('desktop', () => {
  const windowSessionStore = useWindowSessionStore()
  const electronWindowState = ref({ isMaximized: false })
  const apps = createHostDesktopApps()
  migrateDock(apps)
  const runtime = createDesktop({
    apps,
    defaultDockAppIds,
    storageKey: DOCK_APPS_STORAGE_KEY,
    getBounds: () => {
      const settings = useSettingsStore()
      const dockInset = settings.dockAutoHide ? 2 : 76
      return {
        width: Math.max(
          0,
          window.innerWidth - (settings.dockPosition === 'bottom' ? 0 : dockInset),
        ),
        height: Math.max(
          0,
          window.innerHeight - 40 - (settings.dockPosition === 'bottom' ? dockInset : 0),
        ),
      }
    },
    canOpen: (app, windows) =>
      !sessionWindowAppIds.has(app.id) ||
      windows.filter((window) => sessionWindowAppIds.has(window.appId) && !window.isClosing)
        .length < maxSessionWindows,
    onOpenRejected: () =>
      getUiApi().message.warning(`最多只能打开 ${maxSessionWindows} 个会话窗口。`),
    shouldMaximize: () =>
      import.meta.env.VITE_ELECTRON_MAXIMIZE_UI_WHEN_WINDOWED === 'true' &&
      Boolean(window.hostDeck?.window) &&
      !electronWindowState.value.isMaximized,
    onWindowClosed: (window) => windowSessionStore.disconnectWindow(window.id),
    onLifecycleError: (error) => console.error('Desktop lifecycle failed', error),
  })
  runtime.apps['iframe-app']!.actions = [
    { id: 'refresh', label: '刷新', run: (window) => refreshIframeWindow(window.id) },
  ]
  onScopeDispose(() => runtime.dispose())
  const sessionWindowCount = computed(
    () =>
      runtime.windows.filter((window) => sessionWindowAppIds.has(window.appId) && !window.isClosing)
        .length,
  )
  const pinnedDirectoriesByConnection = ref<Record<string, string[]>>(
    Object.fromEntries(
      Object.entries(loadRecord(directoryKey)).map(([key, paths]) => [
        key,
        Array.isArray(paths)
          ? Array.from(
              new Set(
                paths.filter((path): path is string => typeof path === 'string').map(normalize),
              ),
            )
          : [],
      ]),
    ),
  )
  const pinnedDirectoryPositionsByConnection = ref(loadPositions(directoryPositionsKey))
  const pinnedPortLinkPositionsByConnection = ref(loadPositions(portPositionsKey))
  const pinnedPortLinksByConnection = ref<Record<string, PinnedPortLink[]>>(
    Object.fromEntries(
      Object.entries(loadRecord(portLinksKey)).map(([key, links]) => [
        key,
        Array.isArray(links)
          ? links
              .filter(
                (link) =>
                  link &&
                  typeof link.id === 'string' &&
                  typeof link.label === 'string' &&
                  typeof link.url === 'string',
              )
              .map((link) => ({
                id: link.id,
                label: link.label,
                url: link.url,
                host: typeof link.host === 'string' ? link.host : '',
                port: typeof link.port === 'string' ? link.port : '',
                portText: typeof link.portText === 'string' ? link.portText : link.url,
              }))
          : [],
      ]),
    ),
  )

  function connectionKey() {
    const ssh = useSshStore()
    const host = ssh.host.trim()
    const username = ssh.username.trim()
    return host && username && ssh.port !== null ? `${username}@${host}:${ssh.port}` : null
  }
  function getPinnedDirectories() {
    const key = connectionKey()
    return key ? (pinnedDirectoriesByConnection.value[key] ?? []) : []
  }
  function getPinnedDirectoryPositions() {
    const key = connectionKey()
    return key ? (pinnedDirectoryPositionsByConnection.value[key] ?? {}) : {}
  }
  function getPinnedPortLinks() {
    const key = connectionKey()
    return key ? (pinnedPortLinksByConnection.value[key] ?? []) : []
  }
  function getPinnedPortLinkPositions() {
    const key = connectionKey()
    return key ? (pinnedPortLinkPositionsByConnection.value[key] ?? {}) : {}
  }
  function isDirectoryPinned(path: string) {
    return getPinnedDirectories().includes(normalize(path))
  }
  function isPortLinkPinned(url: string) {
    return getPinnedPortLinks().some((link) => link.url === url)
  }
  function setPinnedDirectories(paths: string[]) {
    const key = connectionKey()
    if (!key) return
    const normalizedPaths = Array.from(new Set(paths.map(normalize)))
    const directories = { ...pinnedDirectoriesByConnection.value }
    const positions = { ...pinnedDirectoryPositionsByConnection.value }
    if (!normalizedPaths.length) {
      delete directories[key]
      delete positions[key]
    } else {
      directories[key] = normalizedPaths
      const retained = Object.fromEntries(
        Object.entries(positions[key] ?? {}).filter(([path]) => normalizedPaths.includes(path)),
      )
      if (Object.keys(retained).length) positions[key] = retained
      else delete positions[key]
    }
    pinnedDirectoriesByConnection.value = directories
    pinnedDirectoryPositionsByConnection.value = positions
    persist(directoryKey, directories)
    persist(directoryPositionsKey, positions)
  }
  function pinDirectoryToDesktop(path: string) {
    const target = normalize(path)
    if (isDirectoryPinned(target)) return false
    setPinnedDirectories([...getPinnedDirectories(), target])
    return true
  }
  function unpinDirectoryFromDesktop(paths: string | string[]) {
    const targets = new Set((Array.isArray(paths) ? paths : [paths]).map(normalize))
    setPinnedDirectories(getPinnedDirectories().filter((path) => !targets.has(path)))
  }
  function toggleDirectoryPin(path: string) {
    if (isDirectoryPinned(path)) {
      unpinDirectoryFromDesktop(path)
      return false
    }
    return pinDirectoryToDesktop(path)
  }
  function pinPortLinkToDesktop(link: PinnedPortLink) {
    const key = connectionKey()
    if (!key || isPortLinkPinned(link.url)) return false
    pinnedPortLinksByConnection.value = {
      ...pinnedPortLinksByConnection.value,
      [key]: [...getPinnedPortLinks(), link],
    }
    persist(portLinksKey, pinnedPortLinksByConnection.value)
    return true
  }
  function unpinPortLinkFromDesktop(ids: string | string[]) {
    const key = connectionKey()
    if (!key) return
    const targets = new Set(Array.isArray(ids) ? ids : [ids])
    const links = getPinnedPortLinks().filter((link) => !targets.has(link.id))
    const records = { ...pinnedPortLinksByConnection.value }
    const positions = { ...pinnedPortLinkPositionsByConnection.value }
    if (!links.length) {
      delete records[key]
      delete positions[key]
    } else {
      records[key] = links
      const retained = Object.fromEntries(
        Object.entries(positions[key] ?? {}).filter(([id]) => !targets.has(id)),
      )
      if (Object.keys(retained).length) positions[key] = retained
      else delete positions[key]
    }
    pinnedPortLinksByConnection.value = records
    pinnedPortLinkPositionsByConnection.value = positions
    persist(portLinksKey, records)
    persist(portPositionsKey, positions)
  }
  function togglePortLinkPin(link: PinnedPortLink) {
    if (isPortLinkPinned(link.url)) {
      unpinPortLinkFromDesktop(
        getPinnedPortLinks()
          .filter((item) => item.url === link.url)
          .map((item) => item.id),
      )
      return false
    }
    return pinPortLinkToDesktop(link)
  }
  function setPinnedDirectoryPosition(path: string, x: number, y: number) {
    const key = connectionKey()
    if (!key || !isDirectoryPinned(path) || !Number.isFinite(x) || !Number.isFinite(y)) return
    pinnedDirectoryPositionsByConnection.value = {
      ...pinnedDirectoryPositionsByConnection.value,
      [key]: {
        ...getPinnedDirectoryPositions(),
        [normalize(path)]: { x: Math.round(x), y: Math.round(y) },
      },
    }
    persist(directoryPositionsKey, pinnedDirectoryPositionsByConnection.value)
  }
  function setPinnedPortLinkPosition(id: string, x: number, y: number) {
    const key = connectionKey()
    if (
      !key ||
      !getPinnedPortLinks().some((link) => link.id === id) ||
      !Number.isFinite(x) ||
      !Number.isFinite(y)
    )
      return
    pinnedPortLinkPositionsByConnection.value = {
      ...pinnedPortLinkPositionsByConnection.value,
      [key]: { ...getPinnedPortLinkPositions(), [id]: { x: Math.round(x), y: Math.round(y) } },
    }
    persist(portPositionsKey, pinnedPortLinkPositionsByConnection.value)
  }
  function openPinnedDirectory(path: string) {
    const target = normalize(path)
    return runtime.openWindow('files', {
      path: target,
      title: target === '/' ? '文件管理 · 根目录' : `文件管理 · ${basename(target)}`,
    })
  }
  function openPinnedPortLink(id: string) {
    const link = getPinnedPortLinks().find((item) => item.id === id)
    if (link) window.open(link.url, '_blank', 'noopener')
  }
  function refreshIframeWindow(id: string) {
    if (runtime.windows.find((window) => window.id === id)?.appId === 'iframe-app')
      runtime.updateWindowProps(id, { refreshToken: Date.now() })
  }
  function openWindow(
    appId: DesktopAppId,
    props?: Record<string, unknown>,
    options: OpenWindowOptions = {},
  ) {
    if (appId === 'logout') {
      runtime.reset()
      void useSshStore().clearSession()
      return
    }
    return runtime.openWindow(appId, props, options)
  }
  return {
    ...runtime,
    runtime: markRaw(runtime),
    apps: toRef(runtime, 'apps'),
    windows: toRef(runtime, 'windows'),
    activeWindowId: toRef(runtime, 'activeWindowId'),
    nextZIndex: toRef(runtime, 'nextZIndex'),
    dockAppIds: toRef(runtime, 'dockAppIds'),
    electronWindowState,
    sessionWindowCount,
    openWindow,
    refreshIframeWindow,
    setElectronWindowState(state: { isMaximized: boolean }) {
      electronWindowState.value = { isMaximized: state.isMaximized }
    },
    pinnedDirectoriesByConnection,
    pinnedDirectoryPositionsByConnection,
    pinnedPortLinksByConnection,
    pinnedPortLinkPositionsByConnection,
    getPinnedDirectories,
    getPinnedDirectoryPositions,
    getPinnedPortLinks,
    getPinnedPortLinkPositions,
    isDirectoryPinned,
    isPortLinkPinned,
    setPinnedDirectories,
    pinDirectoryToDesktop,
    unpinDirectoryFromDesktop,
    toggleDirectoryPin,
    pinPortLinkToDesktop,
    unpinPortLinkFromDesktop,
    togglePortLinkPin,
    setPinnedDirectoryPosition,
    setPinnedPortLinkPosition,
    openPinnedDirectory,
    openPinnedPortLink,
  }
})

import { markRaw, reactive } from 'vue'
import type {
  AppConfig,
  DesktopOptions,
  OpenWindowOptions,
  WindowBeforeCloseHandler,
  WindowState,
} from './types'

function browserStorage() {
  try {
    return typeof window === 'undefined' ? null : window.localStorage
  } catch {
    return null
  }
}

/** Each runtime owns its windows, registry, timers and storage namespace. */
export function createDesktop(options: DesktopOptions = {}) {
  const storage = options.storage === undefined ? browserStorage() : options.storage
  const storageKey = options.storageKey ?? 'webos:dock:v1'
  const closeTimers = new Map<ReturnType<typeof setTimeout>, WindowState[]>()
  const bounds = reactive({ width: 1024, height: 720 })
  let disposed = false
  let sequence = 0
  let boundsInitialized = false
  const state = reactive({
    apps: Object.create(null) as Record<string, AppConfig>,
    windows: [] as WindowState[],
    activeWindowId: null as string | null,
    nextZIndex: 100,
    dockAppIds: [] as string[],
  })

  function reportError(error: unknown) {
    if (options.onLifecycleError) options.onLifecycleError(error)
    else console.error('WebOS lifecycle failed', error)
  }

  function persistDock() {
    try {
      storage?.setItem(storageKey, JSON.stringify(state.dockAppIds))
    } catch (error) {
      reportError(error)
    }
  }

  function topWindow() {
    return state.windows
      .filter((window) => !window.isMinimized && !window.isClosing)
      .sort((left, right) => right.zIndex - left.zIndex)[0]
  }

  function windowTree(rootId: string) {
    const result: WindowState[] = []
    const visited = new Set<string>()
    function visit(id: string) {
      if (visited.has(id)) return
      visited.add(id)
      state.windows.filter((window) => window.parentId === id).forEach((window) => visit(window.id))
      const window = state.windows.find((window) => window.id === id)
      if (window) result.push(window)
    }
    visit(rootId)
    return result
  }

  function notifyClosed(windows: WindowState[]) {
    windows.forEach((window) => {
      try {
        Promise.resolve(options.onWindowClosed?.(window)).catch(reportError)
      } catch (error) {
        reportError(error)
      }
    })
  }

  function registerApp(app: AppConfig) {
    if (disposed) throw new Error('Desktop has been disposed.')
    if (!app.id || Object.hasOwn(state.apps, app.id))
      throw new Error(`Duplicate or empty application ID: ${app.id}`)
    if (['__proto__', 'constructor', 'prototype'].includes(app.id))
      throw new Error('Invalid application ID.')
    state.apps[app.id] = { ...app, component: markRaw(app.component) }
  }

  function canOpenWindow(appId: string) {
    const app = state.apps[appId]
    if (disposed || !app) return false
    if (
      (app.singleInstance ?? true) &&
      state.windows.some((window) => window.appId === appId && !window.isClosing)
    )
      return false
    return options.canOpen?.(app, state.windows) ?? true
  }

  function focusWindow(id: string) {
    const target = state.windows.find((window) => window.id === id)
    if (!target || target.isClosing) return
    target.isMinimized = false
    target.zIndex = state.nextZIndex++
    state.activeWindowId = id
  }

  function openWindow(
    appId: string,
    props?: Record<string, unknown>,
    overrides: OpenWindowOptions = {},
  ) {
    const app = state.apps[appId]
    if (disposed || !app) return
    if (overrides.parentId) {
      const parent = state.windows.find((window) => window.id === overrides.parentId)
      if (!parent || parent.isClosing || parent.isClosePending) return
    }
    if (app.singleInstance ?? true) {
      const existing = state.windows.find((window) => window.appId === appId && !window.isClosing)
      if (existing) {
        focusWindow(existing.id)
        return existing.id
      }
    }
    if (!canOpenWindow(appId)) {
      options.onOpenRejected?.(app)
      return
    }
    const minWidth = app.minWidth ?? 320
    const minHeight = app.minHeight ?? 240
    const width = Math.max(app.width ?? 800, minWidth)
    const height = Math.max(app.height ?? 600, minHeight)
    const area = boundsInitialized ? bounds : (options.getBounds?.() ?? bounds)
    const maximizable = overrides.maximizable ?? app.maximizable ?? true
    const defaults = typeof app.defaultProps === 'function' ? app.defaultProps() : app.defaultProps
    const windowProps = defaults || props ? { ...defaults, ...props } : undefined
    const id = `${appId}-${Date.now()}-${sequence++}`
    state.windows.push({
      id,
      appId,
      icon: app.icon,
      title: typeof windowProps?.title === 'string' ? windowProps.title : app.title,
      x: Math.max(16, Math.round((area.width - width) / 2)),
      y: Math.max(16, Math.round((area.height - height) / 2)),
      width,
      height,
      minWidth,
      minHeight,
      maximizable,
      minimizable: overrides.minimizable ?? app.minimizable ?? true,
      resizable: maximizable && (overrides.resizable ?? app.resizable ?? true),
      parentId: overrides.parentId,
      isMinimized: false,
      isMaximized: maximizable && (options.shouldMaximize?.(app) ?? false),
      isClosing: false,
      isClosePending: false,
      zIndex: state.nextZIndex++,
      props: windowProps,
    })
    state.activeWindowId = id
    return id
  }

  function closeWindow(id: string) {
    const target = state.windows.find((window) => window.id === id)
    if (!target || target.isClosing) return
    const tree = windowTree(id).filter((window) => !window.isClosing)
    const ids = new Set(tree.map((window) => window.id))
    tree.forEach((window) => {
      window.isClosing = true
      window.isClosePending = false
    })
    if (state.activeWindowId && ids.has(state.activeWindowId))
      state.activeWindowId = topWindow()?.id ?? null
    const timer = setTimeout(() => {
      closeTimers.delete(timer)
      state.windows = state.windows.filter((window) => !ids.has(window.id))
      notifyClosed(tree)
    }, options.closeAnimationMs ?? 220)
    closeTimers.set(timer, tree)
  }

  async function requestCloseWindow(id: string) {
    const target = state.windows.find((window) => window.id === id)
    if (!target || target.isClosing || target.isClosePending) return false
    const tree = windowTree(id)
    if (tree.some((window) => window.isClosePending)) return false
    tree.forEach((window) => {
      window.isClosePending = true
    })
    try {
      for (const window of tree) {
        if (window.beforeClose && !(await window.beforeClose())) return false
      }
      if (disposed || !state.windows.includes(target) || target.isClosing) return false
      closeWindow(id)
      return true
    } finally {
      tree.forEach((window) => {
        window.isClosePending = false
      })
    }
  }

  function reset() {
    closeTimers.forEach((_, timer) => clearTimeout(timer))
    closeTimers.clear()
    const windows = [...state.windows]
    state.windows = []
    state.activeWindowId = null
    state.nextZIndex = 100
    notifyClosed(windows)
  }

  const runtime = Object.assign(state, {
    reportLifecycleError: reportError,
    registerApp,
    canOpenWindow,
    openWindow,
    closeWindow,
    requestCloseWindow,
    focusWindow,
    restoreWindow: focusWindow,
    reset,
    dispose() {
      if (!disposed) {
        disposed = true
        reset()
      }
    },
    setBounds(width: number, height: number) {
      boundsInitialized = true
      bounds.width = Math.max(0, width)
      bounds.height = Math.max(0, height)
    },
    maximizeWindow(id: string) {
      const target = state.windows.find((window) => window.id === id)
      if (!target || target.isClosing || !target.maximizable) return
      target.isMaximized = !target.isMaximized
      focusWindow(id)
    },
    minimizeWindow(id: string) {
      const target = state.windows.find((window) => window.id === id)
      if (!target || target.isClosing || !target.minimizable) return
      target.isMinimized = true
      if (state.activeWindowId === id) state.activeWindowId = topWindow()?.id ?? null
    },
    closeAppWindows(appId: string) {
      state.windows
        .filter((window) => window.appId === appId)
        .forEach((window) => {
          void requestCloseWindow(window.id).catch(reportError)
        })
    },
    setWindowBeforeClose(id: string, handler?: WindowBeforeCloseHandler) {
      const target = state.windows.find((window) => window.id === id)
      if (target) target.beforeClose = handler
    },
    updateWindowPosition(id: string, x: number, y: number) {
      const target = state.windows.find((window) => window.id === id)
      if (target && Number.isFinite(x) && Number.isFinite(y)) {
        target.x = x
        target.y = y
      }
    },
    updateWindowSize(id: string, width: number, height: number) {
      const target = state.windows.find((window) => window.id === id)
      if (target?.resizable && Number.isFinite(width) && Number.isFinite(height)) {
        target.width = Math.max(target.minWidth, width)
        target.height = Math.max(target.minHeight, height)
      }
    },
    updateWindowProps(id: string, props: Record<string, unknown>) {
      const target = state.windows.find((window) => window.id === id)
      if (target) target.props = { ...target.props, ...props }
    },
    isAppPinnedToDock(appId: string) {
      return state.dockAppIds.includes(appId)
    },
    pinAppToDock(appId: string) {
      if (!state.apps[appId]?.showInLaunchpad || state.dockAppIds.includes(appId)) return false
      state.dockAppIds = [...state.dockAppIds, appId]
      persistDock()
      return true
    },
    unpinAppFromDock(appId: string) {
      if (!state.dockAppIds.includes(appId)) return false
      state.dockAppIds = state.dockAppIds.filter((id) => id !== appId)
      persistDock()
      return true
    },
    moveDockApp(appId: string, targetAppId: string) {
      const from = state.dockAppIds.indexOf(appId)
      const to = state.dockAppIds.indexOf(targetAppId)
      if (from < 0 || to < 0 || from === to) return false
      const next = [...state.dockAppIds]
      next.splice(from, 1)
      next.splice(to, 0, appId)
      state.dockAppIds = next
      persistDock()
      return true
    },
  })
  options.apps?.forEach(registerApp)
  const defaults = options.defaultDockAppIds ?? []
  try {
    const saved: unknown = JSON.parse(storage?.getItem(storageKey) ?? 'null')
    state.dockAppIds = Array.from(
      new Set(
        (Array.isArray(saved) ? saved : defaults).filter(
          (id): id is string => typeof id === 'string' && Boolean(state.apps[id]?.showInLaunchpad),
        ),
      ),
    )
  } catch {
    state.dockAppIds = defaults.filter((id) => state.apps[id]?.showInLaunchpad)
  }
  return runtime
}

export type DesktopRuntime = ReturnType<typeof createDesktop>

import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useDesktopStore } from '@/stores/desktop'

describe('desktop window management', () => {
  beforeEach(() => {
    Object.defineProperty(window, 'matchMedia', {
      configurable: true,
      value: vi.fn().mockReturnValue({
        addEventListener: vi.fn(),
        matches: false,
        removeEventListener: vi.fn(),
      }),
    })
    setActivePinia(createPinia())
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('applies app defaults and per-window capability overrides', () => {
    const store = useDesktopStore()
    const defaultWindowId = store.openWindow('files')
    const restrictedWindowId = store.openWindow('settings', undefined, {
      maximizable: false,
      minimizable: false,
      resizable: true,
    })
    const defaultWindow = store.windows.find((window) => window.id === defaultWindowId)
    const restrictedWindow = store.windows.find((window) => window.id === restrictedWindowId)

    expect(defaultWindow).toMatchObject({
      maximizable: true,
      minimizable: true,
      resizable: true,
    })
    expect(restrictedWindow).toMatchObject({
      maximizable: false,
      minimizable: false,
      resizable: false,
    })

    store.maximizeWindow(restrictedWindowId!)
    store.minimizeWindow(restrictedWindowId!)
    store.updateWindowSize(restrictedWindowId!, 1000, 800)

    expect(restrictedWindow).toMatchObject({
      height: 600,
      isMaximized: false,
      isMinimized: false,
      width: 480,
    })

    expect(store.openWindow('settings')).toBe(restrictedWindowId)
    expect(store.windows.filter((window) => window.appId === 'settings')).toHaveLength(1)
  })

  it('opens configured multi-instance applications in separate windows', () => {
    const store = useDesktopStore()
    const settingsWindowId = store.openWindow('settings')!

    store.minimizeWindow(settingsWindowId)

    expect(store.canOpenWindow('settings')).toBe(false)
    expect(store.openWindow('settings')).toBe(settingsWindowId)
    expect(store.windows.find((window) => window.id === settingsWindowId)?.isMinimized).toBe(false)
    expect(store.windows.filter((window) => window.appId === 'settings')).toHaveLength(1)

    expect(store.canOpenWindow('terminal')).toBe(true)
    expect(store.openWindow('terminal')).not.toBe(store.openWindow('terminal'))
    expect(store.windows.filter((window) => window.appId === 'terminal')).toHaveLength(2)

    expect(store.canOpenWindow('files')).toBe(true)
    expect(store.openWindow('files')).not.toBe(store.openWindow('files'))
    expect(store.windows.filter((window) => window.appId === 'files')).toHaveLength(2)

    expect(store.canOpenWindow('editor')).toBe(true)
    expect(store.openWindow('editor')).not.toBe(store.openWindow('editor'))
    expect(store.windows.filter((window) => window.appId === 'editor')).toHaveLength(2)

    expect(store.canOpenWindow('media-viewer')).toBe(true)
    expect(store.openWindow('media-viewer')).not.toBe(store.openWindow('media-viewer'))
    expect(store.windows.filter((window) => window.appId === 'media-viewer')).toHaveLength(2)
  })

  it('creates nested child windows and rejects an invalid parent', () => {
    const store = useDesktopStore()
    const parentId = store.openWindow('files')!
    const childId = store.openWindow('editor', undefined, { parentId })!
    const grandchildId = store.openWindow('media-viewer', undefined, { parentId: childId })!

    expect(store.windows.find((window) => window.id === childId)?.parentId).toBe(parentId)
    expect(store.windows.find((window) => window.id === grandchildId)?.parentId).toBe(childId)
    expect(store.openWindow('settings', undefined, { parentId: 'missing' })).toBeUndefined()
    expect(store.windows).toHaveLength(3)
  })

  it('cancels the entire close when a descendant refuses to close', async () => {
    const store = useDesktopStore()
    const parentId = store.openWindow('files')!
    const childId = store.openWindow('editor', undefined, { parentId })!
    const parentBeforeClose = vi.fn(() => true)
    const childBeforeClose = vi.fn(() => false)
    store.setWindowBeforeClose(parentId, parentBeforeClose)
    store.setWindowBeforeClose(childId, childBeforeClose)

    await store.requestCloseWindow(parentId)

    expect(childBeforeClose).toHaveBeenCalledOnce()
    expect(parentBeforeClose).not.toHaveBeenCalled()
    expect(store.windows.every((window) => !window.isClosing && !window.isClosePending)).toBe(true)
  })

  it('does not start an overlapping parent close while a child confirmation is pending', async () => {
    const store = useDesktopStore()
    const parentId = store.openWindow('files')!
    const childId = store.openWindow('editor', undefined, { parentId })!
    let resolveChildClose!: (canClose: boolean) => void
    const childBeforeClose = vi.fn(
      () => new Promise<boolean>((resolve) => (resolveChildClose = resolve)),
    )
    const parentBeforeClose = vi.fn(() => true)
    store.setWindowBeforeClose(childId, childBeforeClose)
    store.setWindowBeforeClose(parentId, parentBeforeClose)

    const childCloseRequest = store.requestCloseWindow(childId)
    await store.requestCloseWindow(parentId)

    expect(childBeforeClose).toHaveBeenCalledOnce()
    expect(parentBeforeClose).not.toHaveBeenCalled()

    resolveChildClose(true)
    await childCloseRequest
    expect(store.windows.find((window) => window.id === childId)?.isClosing).toBe(true)
    expect(store.windows.find((window) => window.id === parentId)?.isClosing).toBe(false)
  })

  it('closes descendants before removing the complete window tree', async () => {
    const store = useDesktopStore()
    const parentId = store.openWindow('files')!
    const childId = store.openWindow('editor', undefined, { parentId })!
    const grandchildId = store.openWindow('media-viewer', undefined, { parentId: childId })!
    const closeOrder: string[] = []
    store.setWindowBeforeClose(parentId, () => {
      closeOrder.push(parentId)
      return true
    })
    store.setWindowBeforeClose(childId, () => {
      closeOrder.push(childId)
      return true
    })
    store.setWindowBeforeClose(grandchildId, () => {
      closeOrder.push(grandchildId)
      return true
    })

    await store.requestCloseWindow(parentId)

    expect(closeOrder).toEqual([grandchildId, childId, parentId])
    expect(store.windows.every((window) => window.isClosing)).toBe(true)

    await vi.advanceTimersByTimeAsync(220)
    expect(store.windows).toHaveLength(0)
  })
})

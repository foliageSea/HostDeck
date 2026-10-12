import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createDesktop } from '../desktop'
import type { AppConfig } from '../types'

const component = { render: () => null }
const apps: AppConfig[] = [
  { id: 'single', title: 'Single', icon: '/single.svg', component, showInLaunchpad: true },
  {
    id: 'multi',
    title: 'Multi',
    icon: '/multi.svg',
    component,
    singleInstance: false,
    showInLaunchpad: true,
  },
  {
    id: 'fixed',
    title: 'Fixed',
    icon: '/fixed.svg',
    component,
    maximizable: false,
    minimizable: false,
  },
]

describe('desktop runtime', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    localStorage.clear()
  })
  afterEach(() => vi.useRealTimers())

  it('registers arbitrary apps without product IDs and rejects invalid registrations', () => {
    const desktop = createDesktop({ apps, storage: null })
    desktop.registerApp({ id: 'custom-app', title: 'Custom', icon: '/custom.svg', component })
    expect(desktop.openWindow('custom-app')).toBeTruthy()
    expect(desktop.openWindow('missing')).toBeUndefined()
    expect(desktop.canOpenWindow('toString')).toBe(false)
    expect(() => desktop.registerApp(apps[0]!)).toThrow('Duplicate')
    expect(() => desktop.registerApp({ ...apps[0]!, id: '__proto__' })).toThrow('Invalid')
    desktop.dispose()
  })

  it('preserves singleton focus, multiple instances and window capability overrides', () => {
    const desktop = createDesktop({ apps, storage: null })
    const single = desktop.openWindow('single')!
    desktop.minimizeWindow(single)
    expect(desktop.openWindow('single')).toBe(single)
    expect(desktop.windows[0]?.isMinimized).toBe(false)
    expect(desktop.openWindow('multi')).not.toBe(desktop.openWindow('multi'))
    const fixed = desktop.openWindow('fixed', undefined, { resizable: true })!
    desktop.maximizeWindow(fixed)
    desktop.minimizeWindow(fixed)
    desktop.updateWindowSize(fixed, 1200, 900)
    expect(desktop.windows.find((window) => window.id === fixed)).toMatchObject({
      resizable: false,
      isMaximized: false,
      isMinimized: false,
      width: 800,
      height: 600,
    })
    desktop.dispose()
  })

  it('centers in the measured container instead of the browser viewport', () => {
    const desktop = createDesktop({
      apps: [{ ...apps[0]!, width: 400, height: 300 }],
      storage: null,
      getBounds: () => ({ width: 3000, height: 2000 }),
    })
    desktop.setBounds(900, 600)
    desktop.openWindow('single')
    expect(desktop.windows[0]).toMatchObject({ x: 250, y: 150 })
    expect(desktop.windows[0]).not.toHaveProperty('component')
    desktop.dispose()
  })

  it('delegates open policies and default props to the host', () => {
    const rejected = vi.fn()
    const desktop = createDesktop({
      apps: [{ ...apps[1]!, defaultProps: () => ({ command: 'host-value', override: 'default' }) }],
      storage: null,
      canOpen: (_, windows) => windows.length < 1,
      onOpenRejected: rejected,
      shouldMaximize: () => true,
    })
    desktop.openWindow('multi', { override: 'caller' })
    expect(desktop.windows[0]).toMatchObject({
      props: { command: 'host-value', override: 'caller' },
      isMaximized: true,
    })
    expect(desktop.openWindow('multi')).toBeUndefined()
    expect(rejected).toHaveBeenCalledOnce()
    desktop.dispose()
  })

  it('cancels the whole parent close if a descendant refuses', async () => {
    const closed = vi.fn()
    const desktop = createDesktop({ apps, storage: null, onWindowClosed: closed })
    const parent = desktop.openWindow('single')!
    const child = desktop.openWindow('multi', undefined, { parentId: parent })!
    const parentGuard = vi.fn(() => true)
    desktop.setWindowBeforeClose(parent, parentGuard)
    desktop.setWindowBeforeClose(child, () => false)
    expect(await desktop.requestCloseWindow(parent)).toBe(false)
    expect(parentGuard).not.toHaveBeenCalled()
    expect(desktop.windows.every((window) => !window.isClosing && !window.isClosePending)).toBe(
      true,
    )
    expect(closed).not.toHaveBeenCalled()
    desktop.dispose()
  })

  it('closes child-first and invokes cleanup exactly once after the animation', async () => {
    const closed = vi.fn()
    const guards: string[] = []
    const desktop = createDesktop({ apps, storage: null, onWindowClosed: closed })
    const parent = desktop.openWindow('single')!
    const child = desktop.openWindow('multi', undefined, { parentId: parent })!
    const grandchild = desktop.openWindow('multi', undefined, { parentId: child })!
    ;[parent, child, grandchild].forEach((id) =>
      desktop.setWindowBeforeClose(id, () => {
        guards.push(id)
        return true
      }),
    )
    expect(desktop.openWindow('multi', undefined, { parentId: 'invalid' })).toBeUndefined()
    expect(await desktop.requestCloseWindow(parent)).toBe(true)
    expect(guards).toEqual([grandchild, child, parent])
    expect(closed).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(220)
    expect(closed.mock.calls.map(([window]) => window.id)).toEqual([grandchild, child, parent])
    expect(desktop.windows).toEqual([])
    desktop.dispose()
    expect(closed).toHaveBeenCalledTimes(3)
  })

  it('locks overlapping close requests and resets after a rejected guard', async () => {
    const desktop = createDesktop({ apps, storage: null })
    const parent = desktop.openWindow('single')!
    const child = desktop.openWindow('multi', undefined, { parentId: parent })!
    let resolve!: (value: boolean) => void
    desktop.setWindowBeforeClose(child, () => new Promise<boolean>((done) => (resolve = done)))
    const pending = desktop.requestCloseWindow(child)
    expect(await desktop.requestCloseWindow(parent)).toBe(false)
    resolve(false)
    await pending
    desktop.setWindowBeforeClose(child, () => {
      throw new Error('guard failed')
    })
    await expect(desktop.requestCloseWindow(parent)).rejects.toThrow('guard failed')
    expect(desktop.windows.every((window) => !window.isClosePending)).toBe(true)
    desktop.dispose()
  })

  it('disposes during a pending close without duplicate cleanup or stale timers', async () => {
    const closed = vi.fn()
    const desktop = createDesktop({ apps, storage: null, onWindowClosed: closed })
    const id = desktop.openWindow('single')!
    let resolve!: (value: boolean) => void
    desktop.setWindowBeforeClose(id, () => new Promise<boolean>((done) => (resolve = done)))
    const pending = desktop.requestCloseWindow(id)
    desktop.dispose()
    resolve(true)
    expect(await pending).toBe(false)
    desktop.dispose()
    await vi.runAllTimersAsync()
    expect(closed).toHaveBeenCalledOnce()
    expect(desktop.openWindow('multi')).toBeUndefined()
    expect(vi.getTimerCount()).toBe(0)
  })

  it('resets closing windows once and isolates runtimes and storage namespaces', async () => {
    const closed = vi.fn()
    const left = createDesktop({
      apps,
      storage: localStorage,
      storageKey: 'left',
      defaultDockAppIds: ['single'],
      onWindowClosed: closed,
    })
    const right = createDesktop({
      apps,
      storage: localStorage,
      storageKey: 'right',
      defaultDockAppIds: ['multi'],
    })
    left.pinAppToDock('multi')
    left.moveDockApp('multi', 'single')
    expect(JSON.parse(localStorage.getItem('left')!)).toEqual(['multi', 'single'])
    expect(right.dockAppIds).toEqual(['multi'])
    const id = left.openWindow('single')!
    left.closeWindow(id)
    left.reset()
    await vi.runAllTimersAsync()
    expect(closed).toHaveBeenCalledOnce()
    expect(right.windows).toEqual([])
    left.dispose()
    right.dispose()
  })

  it('recovers from malformed or unavailable storage and reports cleanup errors', async () => {
    const error = vi.fn()
    const desktop = createDesktop({
      apps,
      defaultDockAppIds: ['single'],
      storage: {
        getItem: () => '{bad',
        setItem: () => {
          throw new Error('storage unavailable')
        },
      },
      onWindowClosed: async () => {
        throw new Error('cleanup failed')
      },
      onLifecycleError: error,
    })
    expect(desktop.dockAppIds).toEqual(['single'])
    desktop.pinAppToDock('multi')
    desktop.openWindow('single')
    desktop.dispose()
    await Promise.resolve()
    expect(error).toHaveBeenCalledTimes(2)
  })
})

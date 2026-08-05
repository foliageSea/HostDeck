import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { defaultDockAppIds, DOCK_APPS_STORAGE_KEY, useDesktopStore } from '@/stores/desktop'

describe('desktop dock preferences', () => {
  beforeEach(() => {
    window.localStorage.clear()
    setActivePinia(createPinia())
  })

  it('starts with the default app order', () => {
    expect(useDesktopStore().dockAppIds).toEqual(defaultDockAppIds)
  })

  it('pins, moves and removes apps while persisting the order', () => {
    const store = useDesktopStore()

    expect(store.pinAppToDock('settings')).toBe(true)
    expect(store.moveDockApp('settings', 'files')).toBe(true)
    expect(store.dockAppIds[1]).toBe('settings')
    expect(store.moveDockApp('settings', 'opencode')).toBe(true)
    expect(store.dockAppIds.indexOf('settings')).toBe(store.dockAppIds.indexOf('opencode') + 1)
    expect(store.unpinAppFromDock('terminal')).toBe(true)
    expect(store.dockAppIds).not.toContain('terminal')
    expect(JSON.parse(window.localStorage.getItem(DOCK_APPS_STORAGE_KEY) ?? '[]')).toEqual(
      store.dockAppIds,
    )
  })

  it('restores only valid launchpad applications from storage', () => {
    window.localStorage.setItem(
      DOCK_APPS_STORAGE_KEY,
      JSON.stringify(['settings', 'settings', 'iframe-app', 'unknown']),
    )
    setActivePinia(createPinia())

    expect(useDesktopStore().dockAppIds).toEqual(['settings'])
  })

  it('falls back to defaults when a non-empty stored list has no valid apps', () => {
    window.localStorage.setItem(DOCK_APPS_STORAGE_KEY, JSON.stringify(['removed-app']))
    setActivePinia(createPinia())

    expect(useDesktopStore().dockAppIds).toEqual(defaultDockAppIds)
  })
})

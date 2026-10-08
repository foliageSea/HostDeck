import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { DESKTOP_WIDGETS_STORAGE_KEY, useDesktopWidgetStore } from '@/stores/desktop-widget'

describe('desktop widget management', () => {
  beforeEach(() => {
    window.localStorage.clear()
    setActivePinia(createPinia())
  })

  it('creates the performance widget by default', () => {
    const store = useDesktopWidgetStore()

    expect(store.widgets).toEqual([
      {
        id: 'performance-monitor',
        type: 'performance-monitor',
        x: null,
        y: 24,
      },
    ])
  })

  it('keeps an explicitly empty widget layout after reload', () => {
    const store = useDesktopWidgetStore()
    expect(store.removeWidget('performance-monitor')).toBe(true)
    expect(JSON.parse(window.localStorage.getItem(DESKTOP_WIDGETS_STORAGE_KEY) ?? '')).toEqual([])

    setActivePinia(createPinia())
    expect(useDesktopWidgetStore().widgets).toEqual([])
  })

  it('adds only one instance of a single-instance widget', () => {
    const store = useDesktopWidgetStore()
    const firstId = store.addWidget('performance-monitor')
    const secondId = store.addWidget('performance-monitor')

    expect(firstId).toBe('performance-monitor')
    expect(secondId).toBe(firstId)
    expect(store.widgets).toHaveLength(1)
  })

  it('persists a finite rounded position', () => {
    const store = useDesktopWidgetStore()

    expect(store.updateWidgetPosition('performance-monitor', 123.6, 78.2)).toBe(true)
    expect(store.widgets[0]).toMatchObject({ x: 124, y: 78 })

    setActivePinia(createPinia())
    expect(useDesktopWidgetStore().widgets[0]).toMatchObject({ x: 124, y: 78 })
  })

  it('recovers from malformed storage and filters unknown widget types', () => {
    window.localStorage.setItem(DESKTOP_WIDGETS_STORAGE_KEY, '{bad json')
    expect(useDesktopWidgetStore().widgets).toHaveLength(1)

    setActivePinia(createPinia())
    window.localStorage.setItem(
      DESKTOP_WIDGETS_STORAGE_KEY,
      JSON.stringify([{ id: 'unknown', type: 'unknown', x: 0, y: 0 }]),
    )
    expect(useDesktopWidgetStore().widgets).toEqual([])
  })
})

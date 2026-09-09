import { createPinia, setActivePinia } from 'pinia'
import { nextTick } from 'vue'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useSettingsStore } from '@/stores/settings'

function setPlatform(platform: string, userAgent = '') {
  Object.defineProperty(navigator, 'platform', {
    configurable: true,
    value: platform,
  })
  Object.defineProperty(navigator, 'userAgent', {
    configurable: true,
    value: userAgent,
  })
}

describe('settings window controls style', () => {
  beforeEach(() => {
    window.localStorage.clear()
    Object.defineProperty(window, 'matchMedia', {
      configurable: true,
      value: vi.fn().mockReturnValue({
        addEventListener: vi.fn(),
        matches: false,
        removeEventListener: vi.fn(),
      }),
    })
    setActivePinia(createPinia())
  })

  it('uses macOS controls by default on Apple platforms', () => {
    setPlatform('MacIntel')

    expect(useSettingsStore().windowControlsStyle).toBe('mac')
  })

  it('uses Windows controls by default on non-Apple platforms', () => {
    setPlatform('Linux x86_64')

    expect(useSettingsStore().windowControlsStyle).toBe('win')
  })

  it('keeps an explicitly saved controls style', () => {
    setPlatform('Linux x86_64')
    window.localStorage.setItem('host-deck-ui.windowControlsStyle', 'mac')

    expect(useSettingsStore().windowControlsStyle).toBe('mac')
  })

  it('enables window blur by default and persists a disabled value', async () => {
    const settingsStore = useSettingsStore()

    expect(settingsStore.windowBlur).toBe(true)

    settingsStore.setWindowBlur(false)
    await nextTick()

    expect(window.localStorage.getItem('host-deck-ui.windowBlur')).toBe('false')
  })

  it('persists a custom window switch shortcut', async () => {
    const settingsStore = useSettingsStore()

    settingsStore.setWindowSwitchShortcut({
      altKey: false,
      code: 'KeyK',
      ctrlKey: true,
      ctrlOrMeta: false,
      key: 'k',
      metaKey: false,
      shiftKey: true,
    })
    await nextTick()

    expect(
      JSON.parse(window.localStorage.getItem('host-deck-ui.windowSwitchShortcut') ?? ''),
    ).toEqual(settingsStore.windowSwitchShortcut)
  })
})

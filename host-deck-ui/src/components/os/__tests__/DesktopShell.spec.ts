import { createPinia, setActivePinia } from 'pinia'
import { shallowMount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useDesktopStore } from '@/stores/desktop'
import DesktopShell from '../DesktopShell.vue'

vi.mock('@/components/os/DesktopDock.vue', () => ({ default: { template: '<div />' } }))
vi.mock('@/components/os/DesktopLaunchpad.vue', () => ({ default: { template: '<div />' } }))
vi.mock('@/components/os/DesktopPinnedDirectories.vue', () => ({ default: { template: '<div />' } }))
vi.mock('@/components/os/DesktopTopBar.vue', () => ({ default: { template: '<div />' } }))
vi.mock('@/components/os/DesktopWindow.vue', () => ({ default: { template: '<div />' } }))
vi.mock('@/components/os/DesktopWindowSwitcher.vue', () => ({ default: { template: '<div />' } }))

function setPlatform(platform: string) {
  Object.defineProperty(window.navigator, 'platform', {
    configurable: true,
    value: platform,
  })
}

function dispatchKeyboardEvent(type: 'keydown' | 'keyup', options: KeyboardEventInit) {
  window.dispatchEvent(new KeyboardEvent(type, { bubbles: true, ...options }))
}

describe('DesktopShell', () => {
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

  it('uses Alt+` to switch windows on Windows', () => {
    setPlatform('Win32')
    const desktopStore = useDesktopStore()
    const firstWindowId = desktopStore.openWindow('settings')!
    const secondWindowId = desktopStore.openWindow('dashboard')!
    const wrapper = shallowMount(DesktopShell)

    dispatchKeyboardEvent('keydown', { altKey: true, code: 'Backquote', key: '`' })
    dispatchKeyboardEvent('keyup', { key: 'Alt' })

    expect(desktopStore.activeWindowId).toBe(firstWindowId)

    desktopStore.focusWindow(secondWindowId)
    dispatchKeyboardEvent('keydown', { code: 'Backquote', key: '`', metaKey: true })
    expect(desktopStore.activeWindowId).toBe(secondWindowId)
    wrapper.unmount()
  })

  it('uses Command+` to switch windows on macOS', () => {
    setPlatform('MacIntel')
    const desktopStore = useDesktopStore()
    const firstWindowId = desktopStore.openWindow('settings')!
    const secondWindowId = desktopStore.openWindow('dashboard')!
    const wrapper = shallowMount(DesktopShell)

    dispatchKeyboardEvent('keydown', { code: 'Backquote', key: '`', metaKey: true })
    dispatchKeyboardEvent('keyup', { key: 'Meta' })

    expect(desktopStore.activeWindowId).toBe(firstWindowId)

    desktopStore.focusWindow(secondWindowId)
    dispatchKeyboardEvent('keydown', { altKey: true, code: 'Backquote', key: '`' })
    expect(desktopStore.activeWindowId).toBe(secondWindowId)
    wrapper.unmount()
  })
})

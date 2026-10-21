import { createPinia, setActivePinia } from 'pinia'
import { nextTick } from 'vue'
import { shallowMount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import DesktopWindow from '../DesktopWindow.vue'

describe('DesktopWindow', () => {
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

  it('disables maximize controls and resize interactions in both control styles', async () => {
    const desktopStore = useDesktopStore()
    const settingsStore = useSettingsStore()
    const windowId = desktopStore.openWindow('settings', undefined, {
      maximizable: false,
      resizable: true,
    })!
    const desktopWindow = desktopStore.windows.find((window) => window.id === windowId)!
    const wrapper = shallowMount(DesktopWindow, { props: { window: desktopWindow } })

    expect(desktopWindow.resizable).toBe(false)
    expect(wrapper.get('[aria-label="最大化不可用"]').attributes()).toHaveProperty('disabled')
    expect(wrapper.find('.cursor-nwse-resize').exists()).toBe(false)

    await wrapper.get('header').trigger('dblclick')
    expect(desktopWindow.isMaximized).toBe(false)

    settingsStore.setWindowControlsStyle('win')
    await nextTick()
    expect(wrapper.get('[aria-label="最大化不可用"]').attributes()).toHaveProperty('disabled')
  })

  it('maximizes from the title bar and hides the resize handle', async () => {
    const desktopStore = useDesktopStore()
    const windowId = desktopStore.openWindow('files')!
    const desktopWindow = desktopStore.windows.find((window) => window.id === windowId)!
    const wrapper = shallowMount(DesktopWindow, { props: { window: desktopWindow } })

    expect(wrapper.find('.cursor-nwse-resize').exists()).toBe(true)
    await wrapper.get('header').trigger('dblclick')

    expect(desktopWindow.isMaximized).toBe(true)
    expect(wrapper.find('.cursor-nwse-resize').exists()).toBe(false)
  })

  it('blurs the whole window with a single surface instead of per-section layers', async () => {
    const desktopStore = useDesktopStore()
    const settingsStore = useSettingsStore()
    const windowId = desktopStore.openWindow('settings')!
    const desktopWindow = desktopStore.windows.find((window) => window.id === windowId)!
    const wrapper = shallowMount(DesktopWindow, { props: { window: desktopWindow } })

    settingsStore.setWindowBlur(true)
    await nextTick()
    const windowRoot = wrapper.get('section')
    expect(windowRoot.classes()).toContain('backdrop-blur-[22px]')
    expect(windowRoot.classes()).toContain('[backdrop-filter:blur(22px)_saturate(135%)]')
    expect(wrapper.get('[data-window-title-bar]').classes()).toContain('bg-transparent')
    expect(wrapper.get('[data-window-body]').classes()).toContain('bg-transparent')
    expect(wrapper.get('[data-window-title-bar]').classes()).not.toContain('backdrop-blur-[18px]')
    expect(wrapper.get('[data-window-body]').classes()).not.toContain('backdrop-blur-[22px]')

    settingsStore.setWindowBlur(false)
    await nextTick()
    expect(windowRoot.classes()).not.toContain('backdrop-blur-[22px]')
    expect(windowRoot.classes()).not.toContain('[backdrop-filter:blur(22px)_saturate(135%)]')
    expect(wrapper.get('[data-window-title-bar]').classes()).toContain('bg-white')
    expect(wrapper.get('[data-window-body]').classes()).toContain('bg-white')
  })

  it('adds a border to floating windows only in dark mode', async () => {
    const desktopStore = useDesktopStore()
    const settingsStore = useSettingsStore()
    const windowId = desktopStore.openWindow('files')!
    const desktopWindow = desktopStore.windows.find((window) => window.id === windowId)!
    const wrapper = shallowMount(DesktopWindow, { props: { window: desktopWindow } })

    settingsStore.setTheme('dark')
    await nextTick()
    expect(wrapper.get('section').attributes('style')).toContain(
      'border: 1px solid var(--app-primary-color)',
    )

    settingsStore.setDarkWindowBorder(false)
    await nextTick()
    expect(wrapper.get('section').attributes('style')).not.toContain('--app-primary-color')

    settingsStore.setDarkWindowBorder(true)
    await nextTick()

    desktopStore.maximizeWindow(windowId)
    await nextTick()
    expect(wrapper.get('section').attributes('style')).not.toContain('--app-primary-color')

    desktopStore.maximizeWindow(windowId)
    settingsStore.setTheme('light')
    await nextTick()
    expect(wrapper.get('section').attributes('style')).not.toContain('--app-primary-color')
  })
})

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
      resizable: false,
    })!
    const desktopWindow = desktopStore.windows.find((window) => window.id === windowId)!
    const wrapper = shallowMount(DesktopWindow, { props: { window: desktopWindow } })

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
    const windowId = desktopStore.openWindow('settings')!
    const desktopWindow = desktopStore.windows.find((window) => window.id === windowId)!
    const wrapper = shallowMount(DesktopWindow, { props: { window: desktopWindow } })

    expect(wrapper.find('.cursor-nwse-resize').exists()).toBe(true)
    await wrapper.get('header').trigger('dblclick')

    expect(desktopWindow.isMaximized).toBe(true)
    expect(wrapper.find('.cursor-nwse-resize').exists()).toBe(false)
  })
})

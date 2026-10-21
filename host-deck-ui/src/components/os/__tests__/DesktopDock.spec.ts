import { createPinia, setActivePinia } from 'pinia'
import { nextTick } from 'vue'
import { shallowMount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useDesktopStore } from '@/stores/desktop'
import DesktopDock from '../DesktopDock.vue'

vi.mock('@/hooks/useDockMagnification', () => ({
  useDockMagnification: vi.fn(),
}))

describe('DesktopDock', () => {
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

  function mountDock() {
    return shallowMount(DesktopDock, {
      global: {
        stubs: {
          AppIcon: { template: '<span />' },
          DesktopMenu: true,
          DesktopTooltip: { template: '<div><slot name="trigger" /><slot /></div>' },
        },
      },
    })
  }

  it('shows open child windows in a separate section and restores them', async () => {
    const desktopStore = useDesktopStore()
    const parentId = desktopStore.openWindow('files')!
    const childId = desktopStore.openWindow('editor', { title: '配置文件' }, { parentId })!
    const grandchildId = desktopStore.openWindow(
      'media-viewer',
      { title: '预览图片' },
      { parentId: childId },
    )!
    desktopStore.minimizeWindow(childId)
    const wrapper = mountDock()

    expect(wrapper.find(`[data-dock-window-id="${parentId}"]`).exists()).toBe(false)
    expect(wrapper.findAll('[data-dock-window-id]')).toHaveLength(2)
    expect(wrapper.text()).toContain('配置文件')
    expect(wrapper.text()).toContain('预览图片')

    await wrapper.get(`[data-dock-window-id="${childId}"] button`).trigger('click')

    expect(desktopStore.windows.find((window) => window.id === childId)?.isMinimized).toBe(false)
    expect(desktopStore.activeWindowId).toBe(childId)

    await desktopStore.requestCloseWindow(grandchildId)
    await nextTick()
    expect(wrapper.find(`[data-dock-window-id="${grandchildId}"]`).exists()).toBe(false)
  })

  it('keeps the dock surface centered without a transform so its blur samples the wallpaper', () => {
    const wrapper = mountDock()
    const dock = wrapper.get('.desktop-dock')

    expect(dock.classes()).toContain('relative')
    expect(dock.classes()).not.toContain('absolute')
    expect(dock.attributes('style') ?? '').not.toContain('transform')
    expect(wrapper.get('.dock-hover-zone').classes()).toContain('justify-center')
  })
})

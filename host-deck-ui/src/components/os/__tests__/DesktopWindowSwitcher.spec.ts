import { createPinia, setActivePinia } from 'pinia'
import { shallowMount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import AppIcon from '@/components/common/AppIcon.vue'
import type { WindowState } from '@/stores/desktop'
import DesktopWindowSwitcher from '../DesktopWindowSwitcher.vue'

describe('DesktopWindowSwitcher', () => {
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

  it('uses the same themed application icon as the Dock', () => {
    const windowState = {
      icon: 'terminal',
      id: 'terminal-1',
      title: '终端',
    } as WindowState
    const wrapper = shallowMount(DesktopWindowSwitcher, {
      props: { selectedIndex: 0, windows: [windowState] },
    })

    expect(wrapper.getComponent(AppIcon).props()).toMatchObject({
      name: 'terminal',
      size: 52,
      themed: true,
    })
  })

  it('emits the window id when its close button is clicked', async () => {
    const windowState = {
      icon: 'terminal',
      id: 'terminal-1',
      title: '终端',
    } as WindowState
    const wrapper = shallowMount(DesktopWindowSwitcher, {
      props: { selectedIndex: 0, windows: [windowState] },
    })

    await wrapper.get('button[aria-label="关闭终端"]').trigger('click')

    expect(wrapper.emitted('close')).toEqual([['terminal-1']])
    expect(wrapper.emitted('select')).toBeUndefined()
  })

  it('emits the window index when a window is clicked', async () => {
    const windows = [
      { icon: 'terminal', id: 'terminal-1', title: '终端' },
      { icon: 'settings', id: 'settings-1', title: '设置' },
    ] as WindowState[]
    const wrapper = shallowMount(DesktopWindowSwitcher, {
      props: { selectedIndex: 0, windows },
    })

    await wrapper.get('button[aria-label="切换到设置"]').trigger('click')

    expect(wrapper.emitted('select')).toEqual([[1]])
  })

  it('navigates the window grid with arrow keys and activates with Enter', async () => {
    const windows = Array.from({ length: 5 }, (_, index) => ({
      icon: 'terminal',
      id: `terminal-${index}`,
      title: `终端 ${index}`,
    })) as WindowState[]
    const wrapper = shallowMount(DesktopWindowSwitcher, {
      attachTo: document.body,
      props: { selectedIndex: 1, windows },
    })
    const items = wrapper.findAll('[data-window-index]')
    items.forEach((item, index) => {
      Object.defineProperty(item.element, 'offsetTop', {
        configurable: true,
        value: index < 3 ? 0 : 100,
      })
    })

    await wrapper.get('[tabindex="-1"]').trigger('keydown', { key: 'ArrowDown' })
    expect(wrapper.emitted('highlight')).toEqual([[4]])

    await wrapper.setProps({ selectedIndex: 4 })
    await wrapper.get('[tabindex="-1"]').trigger('keydown', { key: 'ArrowLeft' })
    expect(wrapper.emitted('highlight')).toEqual([[4], [3]])

    await wrapper.setProps({ selectedIndex: 3 })
    await wrapper.get('[tabindex="-1"]').trigger('keydown', { key: 'Enter' })
    expect(wrapper.emitted('select')).toEqual([[3]])
    wrapper.unmount()
  })
})

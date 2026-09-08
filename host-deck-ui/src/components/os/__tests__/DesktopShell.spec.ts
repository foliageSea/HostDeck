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
vi.mock('@/components/os/DesktopWindowSwitcher.vue', () => ({
  default: {
    name: 'DesktopWindowSwitcher',
    emits: ['close', 'highlight', 'select'],
    props: ['selectedIndex', 'windows'],
    template: '<div />',
  },
}))

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

  it('uses Alt+` to show and hide the window switcher on Windows', async () => {
    setPlatform('Win32')
    const desktopStore = useDesktopStore()
    desktopStore.openWindow('settings')
    const secondWindowId = desktopStore.openWindow('dashboard')!
    const wrapper = shallowMount(DesktopShell)

    dispatchKeyboardEvent('keydown', { altKey: true, code: 'Backquote', key: '`' })
    await wrapper.vm.$nextTick()
    expect(wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).exists()).toBe(true)

    dispatchKeyboardEvent('keyup', { key: 'Alt' })
    await wrapper.vm.$nextTick()
    expect(wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).exists()).toBe(true)
    expect(desktopStore.activeWindowId).toBe(secondWindowId)

    dispatchKeyboardEvent('keydown', { altKey: true, code: 'Backquote', key: '`' })
    await wrapper.vm.$nextTick()
    expect(wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).exists()).toBe(false)

    dispatchKeyboardEvent('keydown', { code: 'Backquote', key: '`', metaKey: true })
    await wrapper.vm.$nextTick()
    expect(wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).exists()).toBe(false)
    expect(desktopStore.activeWindowId).toBe(secondWindowId)
    wrapper.unmount()
  })

  it('uses Command+` or Control+` to toggle the window switcher on macOS', async () => {
    setPlatform('MacIntel')
    const desktopStore = useDesktopStore()
    desktopStore.openWindow('settings')
    const secondWindowId = desktopStore.openWindow('dashboard')!
    const wrapper = shallowMount(DesktopShell)

    dispatchKeyboardEvent('keydown', { code: 'Backquote', key: '`', metaKey: true })
    await wrapper.vm.$nextTick()
    expect(wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).exists()).toBe(true)

    dispatchKeyboardEvent('keyup', { key: 'Meta' })
    await wrapper.vm.$nextTick()
    expect(wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).exists()).toBe(true)
    expect(desktopStore.activeWindowId).toBe(secondWindowId)

    dispatchKeyboardEvent('keydown', { code: 'Backquote', key: '`', ctrlKey: true })
    await wrapper.vm.$nextTick()
    expect(wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).exists()).toBe(false)

    dispatchKeyboardEvent('keydown', { altKey: true, code: 'Backquote', key: '`' })
    await wrapper.vm.$nextTick()
    expect(wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).exists()).toBe(false)
    expect(desktopStore.activeWindowId).toBe(secondWindowId)
    wrapper.unmount()
  })

  it('focuses the clicked window and hides the window switcher', async () => {
    setPlatform('Win32')
    const desktopStore = useDesktopStore()
    const firstWindowId = desktopStore.openWindow('settings')!
    desktopStore.openWindow('dashboard')
    const wrapper = shallowMount(DesktopShell)

    dispatchKeyboardEvent('keydown', { altKey: true, code: 'Backquote', key: '`' })
    await wrapper.vm.$nextTick()

    wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).vm.$emit('select', 1)
    await wrapper.vm.$nextTick()

    expect(desktopStore.activeWindowId).toBe(firstWindowId)
    expect(wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).exists()).toBe(false)
    wrapper.unmount()
  })

  it('updates the highlighted window from keyboard grid navigation', async () => {
    setPlatform('Win32')
    const desktopStore = useDesktopStore()
    desktopStore.openWindow('settings')
    desktopStore.openWindow('dashboard')
    const wrapper = shallowMount(DesktopShell)

    dispatchKeyboardEvent('keydown', { altKey: true, code: 'Backquote', key: '`' })
    await wrapper.vm.$nextTick()
    const switcher = wrapper.findComponent({ name: 'DesktopWindowSwitcher' })

    switcher.vm.$emit('highlight', 1)
    await wrapper.vm.$nextTick()

    expect(switcher.props('selectedIndex')).toBe(1)
    wrapper.unmount()
  })
})

import { createPinia, setActivePinia } from 'pinia'
import { shallowMount } from '@vue/test-utils'
import { nextTick } from 'vue'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useDesktopStore } from '@/stores/desktop'
import DesktopTopBar from '../DesktopTopBar.vue'

vi.hoisted(() => {
  Object.defineProperty(globalThis, '__APP_VERSION__', { configurable: true, value: 'test' })
})

describe('DesktopTopBar', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date(2026, 7, 26, 10, 59, 30))
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

  afterEach(() => {
    vi.useRealTimers()
    Reflect.deleteProperty(document, 'exitFullscreen')
    Reflect.deleteProperty(document, 'fullScreen')
    Reflect.deleteProperty(document, 'fullscreenElement')
    Reflect.deleteProperty(document.documentElement, 'requestFullscreen')
  })

  it('updates the displayed time at the next minute', async () => {
    const wrapper = shallowMount(DesktopTopBar)

    expect(wrapper.get('time').text()).toBe('10:59')

    vi.advanceTimersByTime(30_000)
    await nextTick()

    expect(wrapper.get('time').text()).toBe('11:00')
    wrapper.unmount()
  })

  it('opens one task center window and restores it on repeated clicks', async () => {
    const desktopStore = useDesktopStore()
    const wrapper = shallowMount(DesktopTopBar, {
      global: {
        stubs: {
          NBadge: { template: '<div><slot /></div>' },
          NButton: { template: '<button><slot name="icon" /><slot /></button>' },
          NTooltip: { template: '<div><slot name="trigger" /><slot /></div>' },
        },
      },
    })
    const trigger = wrapper.get('[aria-label="打开任务中心"]')

    await trigger.trigger('click')
    const taskCenterWindow = desktopStore.windows.find((window) => window.appId === 'task-center')
    expect(taskCenterWindow).toBeDefined()

    desktopStore.minimizeWindow(taskCenterWindow!.id)
    await trigger.trigger('click')

    expect(desktopStore.windows.filter((window) => window.appId === 'task-center')).toHaveLength(1)
    expect(taskCenterWindow?.isMinimized).toBe(false)
    wrapper.unmount()
  })

  it('toggles browser fullscreen and updates its accessible label', async () => {
    let fullscreenElement: Element | null = null
    const requestFullscreen = vi.fn(async () => {
      fullscreenElement = document.documentElement
      document.dispatchEvent(new Event('fullscreenchange'))
    })
    const exitFullscreen = vi.fn(async () => {
      fullscreenElement = null
      document.dispatchEvent(new Event('fullscreenchange'))
    })
    Object.defineProperties(document, {
      exitFullscreen: { configurable: true, value: exitFullscreen },
      fullScreen: { configurable: true, get: () => fullscreenElement !== null },
      fullscreenElement: { configurable: true, get: () => fullscreenElement },
    })
    Object.defineProperty(document.documentElement, 'requestFullscreen', {
      configurable: true,
      value: requestFullscreen,
    })

    const wrapper = shallowMount(DesktopTopBar, {
      global: {
        stubs: {
          NButton: { template: '<button><slot name="icon" /><slot /></button>' },
          NTooltip: { template: '<div><slot name="trigger" /><slot /></div>' },
        },
      },
    })
    await nextTick()

    const enterButton = wrapper.get('[aria-label="进入网页全屏"]')
    await enterButton.trigger('click')
    await nextTick()

    expect(requestFullscreen).toHaveBeenCalledOnce()
    expect(wrapper.get('[aria-label="退出网页全屏"]')).toBeDefined()

    await wrapper.get('[aria-label="退出网页全屏"]').trigger('click')
    await nextTick()

    expect(exitFullscreen).toHaveBeenCalledOnce()
    expect(wrapper.get('[aria-label="进入网页全屏"]')).toBeDefined()
    wrapper.unmount()
  })
})

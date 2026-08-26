import { createPinia, setActivePinia } from 'pinia'
import { shallowMount } from '@vue/test-utils'
import { nextTick } from 'vue'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
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
  })

  it('updates the displayed time at the next minute', async () => {
    const wrapper = shallowMount(DesktopTopBar)

    expect(wrapper.get('time').text()).toBe('10:59')

    vi.advanceTimersByTime(30_000)
    await nextTick()

    expect(wrapper.get('time').text()).toBe('11:00')
    wrapper.unmount()
  })
})

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
})

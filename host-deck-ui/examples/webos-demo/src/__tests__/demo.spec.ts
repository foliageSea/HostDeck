import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { defineComponent, h, nextTick } from 'vue'
import { DesktopProvider, DesktopWindow } from '@host-deck/webos'
import { createDemoDesktop } from '../desktop'
import App from '../App.vue'

describe('demo consumes built WebOS package', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    localStorage.clear()
    vi.stubGlobal(
      'matchMedia',
      vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })),
    )
    vi.stubGlobal(
      'ResizeObserver',
      class {
        observe() {}
        unobserve() {}
        disconnect() {}
      },
    )
  })
  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
  })

  it('mounts a standalone desktop without an embedding page and keeps overlays inside its root', async () => {
    const wrapper = mount(App, { attachTo: document.body })
    expect(wrapper.find('.demo-page').exists()).toBe(false)
    expect(wrapper.find('h1').exists()).toBe(false)
    expect(wrapper.get('.demo-desktop').element.children).toHaveLength(1)
    expect(wrapper.get('.demo-desktop').element.firstElementChild).toBe(
      wrapper.get('.webos-root').element,
    )
    await wrapper.get('[aria-label="欢迎"]').trigger('click')
    expect(wrapper.get('[data-window-body]').text()).toContain('独立 Vue 桌面')
    await wrapper.get('[aria-label="打开启动台"]').trigger('click')
    await nextTick()
    expect(
      wrapper.get('.webos-root').element.querySelector('[aria-label="应用启动台"]'),
    ).not.toBeNull()
    await wrapper.get('[aria-label="关闭启动台"]').trigger('click')
    wrapper.unmount()
    await vi.runOnlyPendingTimersAsync()
    expect(document.querySelector('[aria-label="应用启动台"]')).toBeNull()
  })

  it('opens singleton and multi-instance demo apps and registers a custom widget', () => {
    const context = createDemoDesktop(null)
    expect(context.desktop.openWindow('welcome')).toBe(context.desktop.openWindow('welcome'))
    expect(context.desktop.openWindow('counter')).not.toBe(context.desktop.openWindow('counter'))
    expect(context.widgets?.widgets[0]?.type).toBe('clock')
    expect(context.desktop.apps).not.toHaveProperty('terminal')
    context.desktop.dispose()
  })

  it('runs the editor close guard from the distributed component', async () => {
    const context = createDemoDesktop(null)
    const id = context.desktop.openWindow('editor')!
    const wrapper = mount(
      defineComponent({
        setup: () => () =>
          h(
            DesktopProvider,
            { context },
            { default: () => h(DesktopWindow, { window: context.desktop.windows[0]! }) },
          ),
      }),
    )
    await wrapper.get('textarea').setValue('unsaved')
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false)
    expect(await context.desktop.requestCloseWindow(id)).toBe(false)
    expect(confirm).toHaveBeenCalledOnce()
    await wrapper.get('article button').trigger('click')
    await nextTick()
    expect(await context.desktop.requestCloseWindow(id)).toBe(true)
    wrapper.unmount()
    await vi.advanceTimersByTimeAsync(220)
    expect(context.desktop.windows).toEqual([])
    context.desktop.dispose()
    confirm.mockRestore()
  })
})

import { createPinia, setActivePinia } from 'pinia'
import { mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useDesktopStore } from '@/stores/desktop'
import { useDesktopWidgetStore } from '@/stores/desktop-widget'
import DesktopWidgets from '../DesktopWidgets.vue'

vi.mock('../PerformanceMonitorWidget.vue', () => ({
  default: { template: '<div data-performance-widget />' },
}))

describe('DesktopWidgets', () => {
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

  function mountWidgets() {
    return mount(DesktopWidgets, {
      global: {
        components: {
          NButton: { template: '<button><slot name="icon" /><slot /></button>' },
          NDropdown: {
            name: 'NDropdown',
            emits: ['select'],
            template: '<div />',
          },
        },
      },
    })
  }

  function dispatchPointer(
    element: Element,
    type: string,
    values: { button?: number; clientX: number; clientY: number; pointerId: number },
  ) {
    const event = new Event(type, { bubbles: true })
    Object.defineProperties(event, {
      button: { value: values.button ?? 0 },
      clientX: { value: values.clientX },
      clientY: { value: values.clientY },
      pointerId: { value: values.pointerId },
    })
    element.dispatchEvent(event)
  }

  it('places the default widget at the top right and persists dragging', async () => {
    const widgetStore = useDesktopWidgetStore()
    const wrapper = mountWidgets()
    Object.defineProperty(wrapper.element, 'clientWidth', { configurable: true, value: 1000 })
    Object.defineProperty(wrapper.element, 'clientHeight', { configurable: true, value: 700 })
    window.dispatchEvent(new Event('resize'))
    await wrapper.vm.$nextTick()
    const widget = wrapper.get('[data-desktop-widget-id="performance-monitor"]')

    expect(widget.attributes('style')).toContain('left: 586px')
    expect(widget.attributes('style')).toContain('top: 24px')

    const dragHandle = wrapper.get('[data-widget-drag-handle]')
    dispatchPointer(dragHandle.element, 'pointerdown', {
      button: 0,
      clientX: 600,
      clientY: 40,
      pointerId: 1,
    })
    dispatchPointer(dragHandle.element, 'pointermove', {
      clientX: 500,
      clientY: 140,
      pointerId: 1,
    })
    dispatchPointer(dragHandle.element, 'pointerup', {
      clientX: 500,
      clientY: 140,
      pointerId: 1,
    })
    await wrapper.vm.$nextTick()

    expect(widgetStore.widgets[0]).toMatchObject({ x: 486, y: 124 })
  })

  it('opens the registered details application', async () => {
    const desktopStore = useDesktopStore()
    const wrapper = mountWidgets()

    await wrapper.get('[aria-label="查看详情"]').trigger('click')

    expect(desktopStore.windows).toHaveLength(1)
    expect(desktopStore.windows[0]?.appId).toBe('dashboard')
    expect(desktopStore.windows[0]?.props).toMatchObject({ initialTab: 'performance' })

    desktopStore.updateWindowProps(desktopStore.windows[0]!.id, { initialTab: 'host' })
    await wrapper.get('[aria-label="查看详情"]').trigger('click')
    expect(desktopStore.windows).toHaveLength(1)
    expect(desktopStore.windows[0]?.props).toMatchObject({ initialTab: 'performance' })
  })

  it('removes a widget from its context menu', async () => {
    const widgetStore = useDesktopWidgetStore()
    const wrapper = mountWidgets()
    const widget = wrapper.get('[data-desktop-widget-id="performance-monitor"]')

    widget.element.dispatchEvent(
      new MouseEvent('contextmenu', { bubbles: true, clientX: 300, clientY: 200 }),
    )
    await wrapper.vm.$nextTick()
    wrapper.findComponent({ name: 'NDropdown' }).vm.$emit('select', 'remove')
    await wrapper.vm.$nextTick()

    expect(widgetStore.widgets).toEqual([])
  })
})

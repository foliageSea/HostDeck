import { defineComponent, h, nextTick } from 'vue'
import { mount } from '@vue/test-utils'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { createDesktop } from '../../core/desktop'
import { createDesktopContext, desktopContextKey } from '../context'
import DesktopWindow from '../DesktopWindow.vue'

function pointer(target: EventTarget, type: string, options: MouseEventInit & { pointerId?: number } = {}) {
  const { pointerId = 1, ...init } = options
  const event = new MouseEvent(type, {
    bubbles: true,
    cancelable: true,
    button: 0,
    buttons: 1,
    clientX: 300,
    clientY: 200,
    ...init,
  })
  Object.defineProperty(event, 'pointerId', { value: pointerId })
  target.dispatchEvent(event)
}

const cleanups: (() => void)[] = []
afterEach(() => {
  cleanups.splice(0).reverse().forEach((cleanup) => cleanup())
  vi.restoreAllMocks()
})

function setup(handle?: string) {
  const desktop = createDesktop({
    storage: null,
    apps: [{
      id: 'custom',
      title: 'Custom',
      icon: '/custom.svg',
      component: defineComponent({ render: () => h('div', 'Content') }),
    }],
  })
  const id = desktop.openWindow('custom')!
  const state = desktop.windows.find((item) => item.id === id)!
  const wrapper = mount(DesktopWindow, {
    attachTo: document.body,
    props: { window: state },
    global: { provide: { [desktopContextKey as symbol]: createDesktopContext(desktop) } },
  })
  cleanups.push(() => { wrapper.unmount(); desktop.dispose() })
  const target = wrapper.get(handle
    ? `[data-window-resize-handle="${handle}"]`
    : '[data-window-title-bar]').element as HTMLElement
  let captured: number | undefined
  const setCapture = vi.fn((pointerId: number) => { captured = pointerId })
  const releaseCapture = vi.fn(() => { captured = undefined })
  Object.assign(target, {
    setPointerCapture: setCapture,
    hasPointerCapture: (pointerId: number) => captured === pointerId,
    releasePointerCapture: releaseCapture,
  })
  const position = vi.spyOn(desktop, 'updateWindowPosition')
  const size = vi.spyOn(desktop, 'updateWindowSize')
  return { desktop, id, state, wrapper, target, setCapture, releaseCapture, position, size }
}

describe.each([undefined, 'se'] as const)('window interaction (%s)', (handle) => {
  it('captures the pointer, updates geometry and releases on pointerup', async () => {
    const { id, state, target, wrapper, setCapture, releaseCapture, position, size } = setup(handle)
    const { x, y, width, height } = state
    pointer(target, 'pointerdown')
    expect(setCapture).toHaveBeenCalledWith(1)
    pointer(window, 'pointermove', { clientX: 330, clientY: 220 })
    if (handle) expect(size).toHaveBeenLastCalledWith(id, width + 30, height + 20)
    else expect(position).toHaveBeenLastCalledWith(id, x + 30, y + 20)
    await nextTick()
    expect(wrapper.classes()).toContain('transition-none')
    pointer(window, 'pointerup', { buttons: 0 })
    expect(releaseCapture).toHaveBeenCalledWith(1)
    position.mockClear()
    size.mockClear()
    pointer(window, 'pointermove')
    expect(position).not.toHaveBeenCalled()
    expect(size).not.toHaveBeenCalled()
    await nextTick()
    expect(wrapper.classes()).not.toContain('transition-none')
  })

  it.each(['buttons', 'blur', 'hidden', 'pointercancel', 'lostpointercapture', 'unmount'])(
    'stops after %s and ignores later movement', async (reason) => {
      const { target, wrapper, releaseCapture, position, size } = setup(handle)
      pointer(target, 'pointerdown')
      if (reason === 'buttons') pointer(window, 'pointermove', { buttons: 0 })
      else if (reason === 'blur') window.dispatchEvent(new Event('blur'))
      else if (reason === 'hidden') {
        vi.spyOn(document, 'hidden', 'get').mockReturnValue(true)
        document.dispatchEvent(new Event('visibilitychange'))
      } else if (reason === 'unmount') wrapper.unmount()
      else pointer(reason === 'lostpointercapture' ? target : window, reason)
      expect(releaseCapture).toHaveBeenCalledWith(1)
      pointer(window, 'pointermove', { clientX: 400, clientY: 300 })
      expect(position).not.toHaveBeenCalled()
      expect(size).not.toHaveBeenCalled()
      await nextTick()
      expect(wrapper.classes()).not.toContain('transition-none')
    },
  )

  it('ignores other pointers and non-left buttons', () => {
    const { target, setCapture, position, size } = setup(handle)
    pointer(target, 'pointerdown', { button: 2, buttons: 2 })
    expect(setCapture).not.toHaveBeenCalled()
    pointer(target, 'pointerdown')
    pointer(window, 'pointerup', { pointerId: 2, buttons: 0 })
    pointer(window, 'pointermove', { pointerId: 2 })
    expect(position).not.toHaveBeenCalled()
    expect(size).not.toHaveBeenCalled()
    pointer(window, 'pointermove')
    expect(handle ? size : position).toHaveBeenCalledOnce()
  })

  it('handles pointerup before a descendant can stop propagation', () => {
    const { target, wrapper, releaseCapture } = setup(handle)
    const body = wrapper.get('[data-window-body]').element
    body.addEventListener('pointerup', (event) => event.stopPropagation())
    pointer(target, 'pointerdown')
    pointer(body, 'pointerup', { buttons: 0 })
    expect(releaseCapture).toHaveBeenCalledWith(1)
  })
})

describe('window title-bar controls', () => {
  it('does not start dragging from controls and still supports double-click maximize', async () => {
    const { wrapper, target, setCapture, desktop } = setup()
    const maximize = vi.spyOn(desktop, 'maximizeWindow')
    pointer(wrapper.get('[data-window-control-action]').element, 'pointerdown')
    expect(setCapture).not.toHaveBeenCalled()
    target.dispatchEvent(new MouseEvent('dblclick', { bubbles: true }))
    expect(maximize).toHaveBeenCalledOnce()
    await nextTick()
    pointer(target, 'pointerdown')
    expect(setCapture).not.toHaveBeenCalled()
  })
})

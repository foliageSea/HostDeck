import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { defineComponent, h, nextTick } from 'vue'
import { mount, shallowMount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createDesktop } from '../../core/desktop'
import { createDesktopContext, desktopContextKey } from '../context'
import DesktopWindow from '../DesktopWindow.vue'
import DesktopShell from '../DesktopShell.vue'
import DesktopProvider from '../DesktopProvider.vue'
import DesktopShortcuts from '../DesktopShortcuts.vue'

describe('standalone desktop components', () => {
  beforeEach(() => {
    vi.stubGlobal(
      'matchMedia',
      vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })),
    )
  })
  afterEach(() => vi.unstubAllGlobals())

  function context() {
    return createDesktopContext(
      createDesktop({
        storage: null,
        apps: [
          {
            id: 'custom',
            title: 'Custom application',
            icon: '/custom.svg',
            component: defineComponent({
              render: () => h('div', { 'data-custom-app': '' }, 'Custom content'),
            }),
            singleInstance: false,
          },
        ],
      }),
    )
  }

  it('renders arbitrary app content and generic title-bar actions without host infrastructure', async () => {
    const value = context()
    const run = vi.fn()
    value.desktop.apps.custom!.actions = [{ id: 'custom-action', label: 'Custom action', run }]
    value.desktop.openWindow('custom')
    const wrapper = mount(DesktopWindow, {
      props: { window: value.desktop.windows[0]! },
      global: { provide: { [desktopContextKey as symbol]: value } },
    })
    expect(wrapper.get('[data-custom-app]').text()).toBe('Custom content')
    await wrapper.get('[aria-label="Custom action"]').trigger('click')
    expect(run).toHaveBeenCalledWith(value.desktop.windows[0])
    wrapper.unmount()
    value.desktop.dispose()
  })

  it('renders icon title-bar actions with dynamic labels and visibility', async () => {
    const value = context()
    const Icon = defineComponent({ render: () => h('svg', { 'data-action-icon': '' }) })
    value.desktop.apps.custom!.actions = [
      {
        id: 'toggle',
        label: (window) => (window.props?.collapsed ? 'Expand' : 'Collapse'),
        icon: () => Icon,
        run: (window) =>
          value.desktop.updateWindowProps(window.id, { collapsed: !window.props?.collapsed }),
      },
      { id: 'hidden', label: 'Hidden', visible: () => false, run: vi.fn() },
    ]
    value.desktop.openWindow('custom')
    const wrapper = mount(DesktopWindow, {
      props: { window: value.desktop.windows[0]! },
      global: { provide: { [desktopContextKey as symbol]: value } },
    })
    expect(wrapper.find('[aria-label="Hidden"]').exists()).toBe(false)
    const button = wrapper.get('[aria-label="Collapse"]')
    expect(button.find('[data-action-icon]').exists()).toBe(true)
    expect(button.text()).toBe('')
    await button.trigger('click')
    await wrapper.setProps({ window: value.desktop.windows[0]! })
    expect(wrapper.find('[aria-label="Expand"]').exists()).toBe(true)
    wrapper.unmount()
    value.desktop.dispose()
  })

  it('measures its container, scopes theme and ignores shortcuts after an outside pointer event', async () => {
    const value = context()
    const wrapper = shallowMount(DesktopShell, {
      global: { provide: { [desktopContextKey as symbol]: value } },
    })
    const content = wrapper.get('main').element
    Object.defineProperties(content, { clientWidth: { value: 900 }, clientHeight: { value: 600 } })
    window.dispatchEvent(new Event('resize'))
    value.desktop.apps.custom!.width = 400
    value.desktop.apps.custom!.height = 300
    const first = value.desktop.openWindow('custom')!
    const second = value.desktop.openWindow('custom')!
    expect(value.desktop.windows[0]).toMatchObject({ x: 250, y: 150 })
    value.preferences.isDark = true
    await nextTick()
    expect(wrapper.attributes('data-theme')).toBe('dark')
    expect(document.documentElement.dataset.theme).toBeUndefined()
    value.preferences.dockPosition = 'left'
    await nextTick()
    expect(wrapper.attributes('data-dock-position')).toBe('left')
    expect(wrapper.get('main').attributes('style')).toContain(
      'left: calc(var(--desktop-dock-edge-gap) + var(--desktop-dock-size))',
    )
    expect(wrapper.get('main').attributes('style')).toContain('bottom: 0px')
    window.dispatchEvent(
      new KeyboardEvent('keydown', { code: 'Backquote', key: '`', altKey: true }),
    )
    window.dispatchEvent(new KeyboardEvent('keyup', { key: 'Alt' }))
    expect(value.desktop.activeWindowId).toBe(first)
    document.body.dispatchEvent(new Event('pointerdown', { bubbles: true }))
    window.dispatchEvent(
      new KeyboardEvent('keydown', { code: 'Backquote', key: '`', altKey: true }),
    )
    window.dispatchEvent(new KeyboardEvent('keyup', { key: 'Alt' }))
    expect(value.desktop.activeWindowId).toBe(first)
    wrapper.element.dispatchEvent(new Event('pointerdown', { bubbles: true }))
    // Mount is detached: exercise activation through document instead in browser integrations.
    value.desktop.focusWindow(second)
    wrapper.unmount()
    expect(value.overlayTarget?.value).toBeNull()
    value.desktop.dispose()
  })

  it('lets the provider own resource disposal when requested', () => {
    const value = context()
    const dispose = vi.spyOn(value.desktop, 'dispose')
    const wrapper = mount(DesktopProvider, { props: { context: value, disposeOnUnmount: true } })
    wrapper.unmount()
    expect(dispose).toHaveBeenCalledOnce()
  })

  it('centers shortcut icons and labels in one column without host utility styles', () => {
    const value = context()
    const style = document.createElement('style')
    style.textContent = readFileSync(resolve(import.meta.dirname, '../../styles.css'), 'utf8')
    document.head.appendChild(style)
    const wrapper = mount(
      defineComponent({
        setup: () => () =>
          h('div', { class: 'webos-root' }, [
            h(DesktopShortcuts, {
              shortcuts: [
                { id: 'custom-shortcut', title: '打开欢迎', icon: '/custom.svg', open: vi.fn() },
              ],
            }),
          ]),
      }),
      { attachTo: document.body, global: { provide: { [desktopContextKey as symbol]: value } } },
    )
    try {
      const shortcut = wrapper.get('.webos-shortcut')
      const computed = getComputedStyle(shortcut.element)
      expect(computed.display).toBe('flex')
      expect(computed.flexDirection).toBe('column')
      expect(computed.alignItems).toBe('center')
      expect(computed.textAlign).toBe('center')
      expect(computed.gap).toBe('6px')
      expect(shortcut.get('img').attributes('width')).toBe('52')
      expect(shortcut.get('.webos-shortcut-label').text()).toBe('打开欢迎')
      expect(getComputedStyle(shortcut.get('.webos-shortcut-label').element).width).toBe('100%')
    } finally {
      wrapper.unmount()
      style.remove()
      value.desktop.dispose()
    }
  })
})

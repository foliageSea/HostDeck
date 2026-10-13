import { defineComponent, h, nextTick, ref } from 'vue'
import { mount, type VueWrapper } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createDesktop } from '../../core/desktop'
import { createDesktopContext, desktopContextKey } from '../context'
import DesktopMenu from '../DesktopMenu.vue'
import DesktopTooltip from '../DesktopTooltip.vue'
import type { DesktopMenuOption } from '../menu-options'

describe('desktop overlays', () => {
  const wrappers: VueWrapper[] = []
  const scrollIntoView = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'scrollIntoView')

  beforeEach(() => {
    vi.useFakeTimers()
    vi.stubGlobal(
      'ResizeObserver',
      class {
        observe() {}
        unobserve() {}
        disconnect() {}
      },
    )
    Object.defineProperty(HTMLElement.prototype, 'scrollIntoView', {
      configurable: true,
      value: vi.fn(),
    })
  })

  afterEach(async () => {
    for (const wrapper of wrappers.splice(0)) wrapper.unmount()
    await vi.advanceTimersByTimeAsync(50)
    vi.restoreAllMocks()
    if (scrollIntoView)
      Object.defineProperty(HTMLElement.prototype, 'scrollIntoView', scrollIntoView)
    else Reflect.deleteProperty(HTMLElement.prototype, 'scrollIntoView')
    vi.unstubAllGlobals()
    vi.useRealTimers()
  })

  async function settle() {
    await nextTick()
    await vi.advanceTimersByTimeAsync(50)
    await nextTick()
  }

  function menu(options: DesktopMenuOption[]) {
    const context = createDesktopContext(createDesktop({ apps: [], storage: null }))
    const show = ref(false)
    const select = vi.fn()
    const wrapper = mount(
      defineComponent({
        setup: () => () =>
          h('div', { ref: context.overlayTarget, class: 'webos-root', 'data-theme': 'dark' }, [
            h('button', { class: 'menu-trigger', onClick: () => (show.value = true) }, '打开菜单'),
            h('button', { class: 'outside' }, '其他操作'),
            h(DesktopMenu, {
              show: show.value,
              x: 120,
              y: 80,
              options,
              onClose: () => (show.value = false),
              onSelect: (key: string) => {
                select(key)
                show.value = false
              },
            }),
          ]),
      }),
      { attachTo: document.body, global: { provide: { [desktopContextKey as symbol]: context } } },
    )
    wrappers.push(wrapper)
    return { wrapper, show, select }
  }

  it('keeps the menu in its desktop, skips disabled items and selects with the keyboard', async () => {
    const { wrapper, select, show } = menu([
      { key: 'disabled', label: '不可用', disabled: true },
      { key: 'open', label: '新建窗口' },
      { key: 'remove', label: '移除', danger: true },
    ])
    await wrapper.get('.menu-trigger').trigger('click')
    await settle()
    const content = wrapper.get('[role="menu"]')
    expect(content.element.closest('.webos-root')).toBe(wrapper.element)
    expect(document.body.style.pointerEvents).not.toBe('none')
    expect(document.documentElement.dataset.theme).toBeUndefined()
    expect(wrapper.get('.webos-danger').text()).toBe('移除')
    await wrapper.get('[data-disabled]').trigger('click')
    expect(select).not.toHaveBeenCalled()
    await content.trigger('keydown', { key: 'ArrowDown' })
    await settle()
    expect(document.activeElement?.textContent).toBe('新建窗口')
    document.activeElement?.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }),
    )
    await settle()
    expect(select).toHaveBeenCalledExactlyOnceWith('open')
    expect(show.value).toBe(false)
    expect(wrapper.find('[role="menu"]').exists()).toBe(false)
  })

  it('restores keyboard focus on Escape but preserves focus when clicking outside', async () => {
    const { wrapper, show } = menu([{ key: 'open', label: '新建窗口' }])
    const trigger = wrapper.get<HTMLButtonElement>('.menu-trigger')
    trigger.element.focus()
    await trigger.trigger('click')
    await settle()
    await wrapper.get('[role="menu"]').trigger('keydown', { key: 'Escape' })
    await settle()
    expect(show.value).toBe(false)
    expect(document.activeElement).toBe(trigger.element)

    await trigger.trigger('click')
    await settle()
    const outside = wrapper.get<HTMLButtonElement>('.outside')
    outside.element.dispatchEvent(new MouseEvent('pointerdown', { button: 0, bubbles: true }))
    outside.element.focus()
    await settle()
    expect(show.value).toBe(false)
    expect(document.activeElement).toBe(outside.element)
  })

  it('supports nested menus and keeps submenu portals in the same desktop', async () => {
    const { wrapper, select, show } = menu([
      { key: 'empty', label: '没有可用小组件', children: [] },
      {
        key: 'widgets',
        label: '添加小组件',
        children: [
          { key: 'clock', label: '时钟', disabled: true },
          { key: 'notes', label: '便签' },
        ],
      },
    ])
    await wrapper.get('.menu-trigger').trigger('click')
    await settle()
    expect(wrapper.get('[data-disabled]').text()).toBe('没有可用小组件')
    const submenuTrigger = wrapper.findAll('[aria-haspopup="menu"]')[1]!
    await submenuTrigger.trigger('keydown', { key: 'ArrowRight' })
    await settle()
    const menus = wrapper.findAll('[role="menu"]')
    expect(menus).toHaveLength(2)
    expect(menus[1]!.element.closest('.webos-root')).toBe(wrapper.element)
    await menus[1]!.trigger('keydown', { key: 'ArrowDown' })
    await settle()
    expect(document.activeElement?.textContent).toBe('便签')
    document.activeElement?.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }),
    )
    await settle()
    expect(select).toHaveBeenCalledExactlyOnceWith('notes')
    expect(show.value).toBe(false)
  })

  it('shows delayed tooltips inside the desktop without adding a trigger wrapper', async () => {
    const context = createDesktopContext(createDesktop({ apps: [], storage: null }))
    const wrapper = mount(
      defineComponent({
        setup: () => () =>
          h('div', { ref: context.overlayTarget, class: 'webos-root' }, [
            h(
              DesktopTooltip,
              {},
              {
                trigger: () => h('button', { class: 'tooltip-trigger' }, '启动台'),
                default: () => '打开启动台',
              },
            ),
          ]),
      }),
      { attachTo: document.body, global: { provide: { [desktopContextKey as symbol]: context } } },
    )
    wrappers.push(wrapper)
    const trigger = wrapper.get('.tooltip-trigger')
    expect(trigger.element.parentElement).toBe(wrapper.element)
    await trigger.trigger('pointermove', { pointerType: 'mouse' })
    expect(wrapper.find('.webos-tooltip').exists()).toBe(false)
    await vi.advanceTimersByTimeAsync(350)
    await settle()
    expect(wrapper.get('.webos-tooltip').element.closest('.webos-root')).toBe(wrapper.element)
    const descriptionId = trigger.attributes('aria-describedby')
    expect(document.getElementById(descriptionId)?.getAttribute('role')).toBe('tooltip')
    await trigger.trigger('click')
    await settle()
    expect(wrapper.find('.webos-tooltip').exists()).toBe(false)
  })
})

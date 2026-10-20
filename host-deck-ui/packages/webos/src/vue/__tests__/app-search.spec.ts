import { defineComponent, h, nextTick } from 'vue'
import { mount, type VueWrapper } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createDesktop } from '../../core/desktop'
import { createDefaultAppSearchShortcut, type KeyboardShortcut } from '../../core/keyboard-shortcut'
import type { DesktopOptions } from '../../core/types'
import { createDesktopContext, desktopContextKey } from '../context'
import DesktopShell from '../DesktopShell.vue'

describe('application quick search', () => {
  const wrappers: VueWrapper[] = []
  const runtimes: ReturnType<typeof createDesktop>[] = []
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
    for (const runtime of runtimes.splice(0)) runtime.dispose()
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
    await vi.dynamicImportSettled()
    await vi.advanceTimersByTimeAsync(50)
    await nextTick()
  }

  function key(target: EventTarget, options: KeyboardEventInit) {
    const event = new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...options })
    target.dispatchEvent(event)
    return event
  }

  function searchKey(options: KeyboardEventInit = {}) {
    return key(window, { key: 'k', code: 'KeyK', ctrlKey: true, ...options })
  }

  function shell(
    options: Partial<DesktopOptions> = {},
    props: { appSearchShortcut?: KeyboardShortcut | null } = {},
  ) {
    const component = defineComponent({ render: () => h('input', { 'aria-label': '应用内容' }) })
    const desktop = createDesktop({
      storage: null,
      apps: [
        {
          id: 'notes',
          title: '便签',
          icon: '/notes.svg',
          component,
          showInLaunchpad: true,
          singleInstance: false,
        },
        {
          id: 'terminal',
          title: 'Terminal',
          icon: '/terminal.svg',
          component,
          showInLaunchpad: true,
        },
        {
          id: 'blocked',
          title: '受限应用',
          icon: '/blocked.svg',
          component,
          showInLaunchpad: true,
        },
        {
          id: 'hidden',
          title: '隐藏应用',
          icon: '/hidden.svg',
          component,
          showInLaunchpad: true,
          hide: true,
        },
        { id: 'internal', title: '内部应用', icon: '/internal.svg', component },
      ],
      canOpen: (app) => app.id !== 'blocked',
      ...options,
    })
    runtimes.push(desktop)
    const context = createDesktopContext(desktop)
    const wrapper = mount(DesktopShell, {
      props,
      attachTo: document.body,
      slots: {
        status: () => [
          h('input', { 'data-origin': '', 'aria-label': '宿主输入' }),
          h('input', { 'data-shortcut-recorder': '', 'aria-label': '录制快捷键' }),
        ],
      },
      global: {
        provide: { [desktopContextKey as symbol]: context },
        stubs: {
          DesktopDock: {
            emits: ['openLaunchpad'],
            template:
              '<button data-open-launchpad @click="$emit(\'openLaunchpad\')">启动台</button>',
          },
          DesktopLaunchpad: { props: ['show'], template: '<section v-if="show" data-launchpad />' },
          DesktopWindowSwitcher: true,
        },
      },
    })
    wrappers.push(wrapper)
    return { wrapper, context, desktop }
  }

  it('opens with Ctrl+K or Command+K, scopes the overlay and focuses the input', async () => {
    const { wrapper, context } = shell()
    context.preferences.isDark = true
    const event = searchKey()
    await settle()
    expect(event.defaultPrevented).toBe(true)
    expect(wrapper.get('.webos-app-search').element.closest('.webos-root')).toBe(wrapper.element)
    expect(wrapper.attributes('data-theme')).toBe('dark')
    expect(document.documentElement.dataset.theme).toBeUndefined()
    expect(document.body.style.pointerEvents).not.toBe('none')
    const input = wrapper.get('[role="combobox"]')
    expect(document.activeElement).toBe(input.element)
    expect(wrapper.findAll('[role="option"]')).toHaveLength(3)
    expect(wrapper.text()).not.toContain('隐藏应用')
    expect(wrapper.text()).not.toContain('内部应用')
    key(input.element, { key: 'Escape' })
    await settle()
    expect(wrapper.find('.webos-app-search').exists()).toBe(false)
    searchKey({ ctrlKey: false, metaKey: true })
    await settle()
    expect(wrapper.find('.webos-app-search').exists()).toBe(true)
  })

  it('filters by title and ID without case or surrounding whitespace and handles no results', async () => {
    const { wrapper, desktop } = shell()
    searchKey()
    await settle()
    const input = wrapper.get('[role="combobox"]')
    await input.setValue('  TERMINAL  ')
    await settle()
    expect(wrapper.findAll('[role="option"]')).toHaveLength(1)
    expect(wrapper.get('[role="option"]').text()).toBe('Terminal')
    expect(wrapper.get('[data-highlighted]').text()).toBe('Terminal')
    await input.setValue('便')
    await settle()
    expect(wrapper.get('[role="option"]').text()).toBe('便签')
    expect(wrapper.get('[data-highlighted]').text()).toBe('便签')
    await input.setValue('NOTES')
    await settle()
    expect(wrapper.get('[role="option"]').text()).toBe('便签')
    await input.setValue('missing')
    await settle()
    expect(wrapper.get('[role="status"]').text()).toBe('未找到应用')
    key(input.element, { key: 'Enter' })
    await settle()
    expect(desktop.windows).toHaveLength(0)
    expect(wrapper.find('.webos-app-search').exists()).toBe(true)
  })

  it('filters by full pinyin or fuzzy initials and updates the index after renaming', async () => {
    const { wrapper, desktop } = shell()
    desktop.apps.notes!.title = '文件管理'
    searchKey()
    await settle()
    const input = wrapper.get('[role="combobox"]')
    for (const query of ['wenjianguanli', 'wen jian', 'WJGL', 'wgl']) {
      await input.setValue(query)
      await settle()
      expect(wrapper.get('[role="option"]').text()).toBe('文件管理')
    }
    desktop.apps.notes!.title = '应用商店'
    await settle()
    expect(wrapper.findAll('[role="option"]')).toHaveLength(0)
    await input.setValue('yysd')
    await settle()
    expect(wrapper.get('[role="option"]').text()).toBe('应用商店')
    key(input.element, { key: 'Enter' })
    await settle()
    expect(desktop.windows[0]?.appId).toBe('notes')
  })

  it('reuses pinyin indexes while typing instead of converting titles on every input', async () => {
    const pinyinSearch = await import('../../core/app-search')
    const index = vi.spyOn(pinyinSearch, 'createPinyinSearchIndex')
    const { wrapper, desktop } = shell()
    expect(index).not.toHaveBeenCalled()
    searchKey()
    await settle()
    expect(index).toHaveBeenCalledTimes(3)
    for (const query of ['b', 'bj', 'notes', '']) {
      await wrapper.get('[role="combobox"]').setValue(query)
      await settle()
    }
    expect(index).toHaveBeenCalledTimes(3)
    desktop.apps.notes!.title = '文件管理'
    await settle()
    expect(index).toHaveBeenCalledTimes(6)
  })

  it('highlights the first result, navigates and launches with Enter into the focused window', async () => {
    const { wrapper, desktop } = shell()
    searchKey()
    await settle()
    const input = wrapper.get('[role="combobox"]')
    expect(wrapper.get('[data-highlighted]').text()).toBe('便签')
    key(input.element, { key: 'ArrowDown' })
    await settle()
    expect(wrapper.get('[data-highlighted]').text()).toBe('Terminal')
    key(input.element, { key: 'ArrowDown' })
    await settle()
    expect(wrapper.get('[data-highlighted]').text()).toBe('便签')
    key(input.element, { key: 'ArrowUp' })
    await settle()
    expect(wrapper.get('[data-highlighted]').text()).toBe('Terminal')
    key(input.element, { key: 'Enter' })
    await settle()
    expect(desktop.windows).toHaveLength(1)
    expect(desktop.windows[0]?.appId).toBe('terminal')
    expect(wrapper.find('.webos-app-search').exists()).toBe(false)
    expect(document.activeElement).toBe(wrapper.get('[data-desktop-window-id]').element)
  })

  it('restores the most recent existing window instead of creating another instance', async () => {
    const { wrapper, desktop } = shell()
    const first = desktop.openWindow('notes')!
    const second = desktop.openWindow('notes')!
    desktop.minimizeWindow(second)
    searchKey()
    await settle()
    await wrapper.get('[role="combobox"]').setValue('notes')
    await settle()
    expect(wrapper.get('[role="option"]').text()).toContain('已打开')
    await wrapper.get('[role="option"]').trigger('click')
    await settle()
    expect(desktop.windows).toHaveLength(2)
    expect(desktop.activeWindowId).toBe(second)
    expect(desktop.windows.find((window) => window.id === second)?.isMinimized).toBe(false)
    expect(document.activeElement?.getAttribute('data-desktop-window-id')).toBe(second)
    expect(desktop.activeWindowId).not.toBe(first)
  })

  it('disables unavailable apps but still allows restoring an existing singleton', async () => {
    const { wrapper, desktop } = shell()
    desktop.openWindow('terminal')
    searchKey()
    await settle()
    const unavailable = wrapper.get('[data-disabled]')
    expect(unavailable.text()).toContain('受限应用')
    await unavailable.trigger('click')
    expect(desktop.windows).toHaveLength(1)
    expect(wrapper.find('.webos-app-search').exists()).toBe(true)
    await wrapper.get('[role="combobox"]').setValue('terminal')
    await settle()
    expect(wrapper.get('[role="option"]').attributes('data-disabled')).toBeUndefined()
    key(wrapper.get('[role="combobox"]').element, { key: 'Enter' })
    await settle()
    expect(desktop.windows).toHaveLength(1)
    expect(wrapper.find('.webos-app-search').exists()).toBe(false)
  })

  it('keeps search open when the runtime rejects a launch after the list was rendered', async () => {
    let allowed = true
    const rejected = vi.fn()
    const { wrapper, desktop } = shell({ canOpen: () => allowed, onOpenRejected: rejected })
    searchKey()
    await settle()
    await wrapper.get('[role="combobox"]').setValue('notes')
    await settle()
    allowed = false
    await wrapper.get('[role="option"]').trigger('click')
    await settle()
    expect(rejected).toHaveBeenCalledOnce()
    expect(desktop.windows).toHaveLength(0)
    expect(wrapper.find('.webos-app-search').exists()).toBe(true)
  })

  it('updates the results when apps are registered while search is open', async () => {
    const { wrapper, desktop } = shell()
    searchKey()
    await settle()
    await wrapper.get('[role="combobox"]').setValue('custom')
    await settle()
    expect(wrapper.findAll('[role="option"]')).toHaveLength(0)
    desktop.registerApp({
      id: 'custom',
      title: '自定义应用',
      icon: '/custom.svg',
      showInLaunchpad: true,
      component: defineComponent({ render: () => h('div', '自定义内容') }),
    })
    await settle()
    expect(wrapper.get('[role="option"]').text()).toBe('自定义应用')
    key(wrapper.get('[role="combobox"]').element, { key: 'Enter' })
    await settle()
    expect(desktop.windows[0]?.appId).toBe('custom')
  })

  it('restores focus on Escape, resets the query on reopening and closes on backdrop click', async () => {
    const { wrapper } = shell()
    const origin = wrapper.get<HTMLInputElement>('[data-origin]')
    origin.element.focus()
    searchKey()
    await settle()
    await wrapper.get('[role="combobox"]').setValue('terminal')
    key(wrapper.get('[role="combobox"]').element, { key: 'Escape' })
    await settle()
    expect(document.activeElement).toBe(origin.element)
    searchKey()
    await settle()
    expect(wrapper.get<HTMLInputElement>('[role="combobox"]').element.value).toBe('')
    wrapper
      .get('.webos-app-search-layer')
      .element.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }))
    await settle()
    expect(wrapper.find('.webos-app-search').exists()).toBe(false)
  })

  it('ignores repeats, unrelated modifiers, composition and shortcut recorder input', async () => {
    const { wrapper } = shell()
    searchKey({ repeat: true })
    searchKey({ shiftKey: true })
    searchKey({ altKey: true })
    searchKey({ isComposing: true })
    key(wrapper.get('[data-shortcut-recorder]').element, { key: 'k', code: 'KeyK', ctrlKey: true })
    await settle()
    expect(wrapper.find('.webos-app-search').exists()).toBe(false)
    searchKey()
    await settle()
    const input = wrapper.get('[role="combobox"]')
    await input.trigger('compositionstart')
    key(input.element, { key: 'Enter', isComposing: true })
    key(input.element, { key: 'Escape', isComposing: true })
    await settle()
    expect(wrapper.find('.webos-app-search').exists()).toBe(true)
    await input.trigger('compositionend')
  })

  it('only handles shortcuts in the activated desktop and leaves outside focus alone', async () => {
    const first = shell()
    const second = shell()
    second.wrapper.get<HTMLInputElement>('[data-origin]').element.focus()
    searchKey()
    await settle()
    expect(first.wrapper.find('.webos-app-search').exists()).toBe(false)
    expect(second.wrapper.find('.webos-app-search').exists()).toBe(true)
    first.wrapper.get<HTMLInputElement>('[data-origin]').element.focus()
    await settle()
    expect(second.wrapper.find('.webos-app-search').exists()).toBe(false)
    expect(document.activeElement).toBe(first.wrapper.get('[data-origin]').element)
    searchKey()
    await settle()
    expect(first.wrapper.find('.webos-app-search').exists()).toBe(true)
    document.body.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }))
    await settle()
    expect(first.wrapper.find('.webos-app-search').exists()).toBe(false)
    expect(searchKey().defaultPrevented).toBe(false)
    await settle()
    expect(first.wrapper.find('.webos-app-search').exists()).toBe(false)
    expect(second.wrapper.find('.webos-app-search').exists()).toBe(false)
  })

  it('allows custom or disabled shortcuts and preserves configured window-switch shortcuts', async () => {
    const custom = { ...createDefaultAppSearchShortcut(), code: 'KeyP', key: 'p' }
    const { wrapper, context, desktop } = shell({}, { appSearchShortcut: custom })
    expect(searchKey().defaultPrevented).toBe(false)
    key(window, { key: 'p', code: 'KeyP', ctrlKey: true })
    await settle()
    expect(wrapper.find('.webos-app-search').exists()).toBe(true)
    await wrapper.get('[aria-label="关闭快捷搜索"]').trigger('click')
    await settle()
    await wrapper.setProps({ appSearchShortcut: null })
    expect(key(window, { key: 'p', code: 'KeyP', ctrlKey: true }).defaultPrevented).toBe(false)
    await wrapper.setProps({ appSearchShortcut: undefined })
    desktop.openWindow('notes')
    desktop.openWindow('notes')
    context.preferences.windowSwitchShortcut = createDefaultAppSearchShortcut()
    searchKey()
    await settle()
    expect(wrapper.find('.webos-app-search').exists()).toBe(false)
    expect(wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).exists()).toBe(true)
  })

  it('keeps quick search mutually exclusive with the launchpad and window switcher', async () => {
    const { wrapper, desktop } = shell()
    await wrapper.get('[data-open-launchpad]').trigger('click')
    expect(wrapper.find('[data-launchpad]').exists()).toBe(true)
    searchKey()
    await settle()
    expect(wrapper.find('[data-launchpad]').exists()).toBe(false)
    expect(wrapper.find('.webos-app-search').exists()).toBe(true)
    await wrapper.get('[aria-label="关闭快捷搜索"]').trigger('click')
    await settle()
    desktop.openWindow('notes')
    desktop.openWindow('notes')
    key(window, { key: '`', code: 'Backquote', altKey: true, shiftKey: true })
    await settle()
    expect(wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).exists()).toBe(true)
    searchKey()
    await settle()
    expect(wrapper.findComponent({ name: 'DesktopWindowSwitcher' }).exists()).toBe(false)
    expect(wrapper.find('.webos-app-search').exists()).toBe(true)
  })
})

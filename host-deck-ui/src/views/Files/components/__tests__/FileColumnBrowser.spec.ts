import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { filesApi, type FileItem } from '@/api/files'
import FileColumnBrowser from '../FileColumnBrowser.vue'

vi.mock('@/api/files', () => ({
  filesApi: { list: vi.fn() },
}))

vi.mock('@/stores/settings', () => ({
  useSettingsStore: () => ({ isDark: false }),
}))

const directory = (filename: string): FileItem => ({
  filename,
  isDirectory: true,
  longname: filename,
  size: 0,
})

const file = (filename: string): FileItem => ({
  filename,
  isDirectory: false,
  longname: filename,
  size: 1,
})

function createWrapper(currentPath = '/var') {
  return mount(FileColumnBrowser, {
    props: {
      connectionId: 'conn-1',
      currentPath,
      search: '',
      selectedNames: [],
      selectionPath: '/',
      sortDirection: 'asc',
      sortKey: 'name',
    },
    global: {
      stubs: {
        FileMediaPreview: { template: '<span data-testid="preview" />' },
      },
    },
  })
}

describe('FileColumnBrowser', () => {
  beforeEach(() => {
    vi.mocked(filesApi.list).mockReset()
  })

  it('loads each directory in the current path as a column', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var'), directory('home')])
      .mockResolvedValueOnce([file('notes.txt')])

    const wrapper = createWrapper()
    await flushPromises()

    expect(filesApi.list).toHaveBeenNthCalledWith(1, 'conn-1', '/')
    expect(filesApi.list).toHaveBeenNthCalledWith(2, 'conn-1', '/var')
    expect(wrapper.findAll('section')).toHaveLength(2)
    expect(wrapper.text()).toContain('notes.txt')
  })

  it('selects and expands a directory with one click', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockResolvedValueOnce([file('notes.txt')])

    const wrapper = createWrapper()
    await flushPromises()
    await wrapper.findAll('[data-file-name]')[0]!.trigger('click')

    expect(wrapper.emitted('clickFile')?.[0]?.[0]).toBe('/')
    expect(wrapper.emitted('activateDirectory')).toEqual([['/var']])

    await wrapper.setProps({ selectedNames: ['var'], selectionPath: '/' })
    expect(wrapper.findAll('[data-file-name]')[0]!.attributes('aria-selected')).toBe('true')
    expect(wrapper.findAll('[data-file-name]')[0]!.classes()).toContain('file-column-item-selected')
  })

  it('filters only the active column', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var'), directory('home')])
      .mockResolvedValueOnce([file('notes.txt'), file('access.log')])

    const wrapper = createWrapper()
    await flushPromises()
    await wrapper.setProps({ search: 'notes' })

    expect(wrapper.text()).toContain('home')
    expect(wrapper.text()).toContain('notes.txt')
    expect(wrapper.text()).not.toContain('access.log')
  })

  it('resizes columns and scrolls horizontally with shift-wheel', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockResolvedValueOnce([file('notes.txt')])

    const wrapper = createWrapper()
    await flushPromises()
    const firstColumn = wrapper.findAll('section')[0]!
    wrapper
      .findAll('[role="separator"]')[0]!
      .element.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, clientX: 100 }))
    window.dispatchEvent(new MouseEvent('pointermove', { clientX: 160 }))
    await wrapper.vm.$nextTick()

    expect(firstColumn.attributes('style')).toContain('width: 320px')

    const scroller = wrapper.get('[data-testid="file-column-browser"]')
    Object.defineProperty(scroller.element, 'scrollLeft', { value: 0, writable: true })
    scroller.element.dispatchEvent(
      new WheelEvent('wheel', { bubbles: true, deltaY: 80, shiftKey: true }),
    )
    expect(scroller.element.scrollLeft).toBe(80)
  })
})

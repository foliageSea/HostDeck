import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { filesApi, type FileItem } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { resetNotifyOnceCache } from '../../utils/fileError'
import FileColumnBrowser from '../FileColumnBrowser.vue'

vi.mock('@/api/files', () => ({
  filesApi: { list: vi.fn() },
}))

vi.mock('@/stores/settings', () => ({
  useSettingsStore: () => ({ isDark: false }),
}))

const messageError = vi.fn()

vi.mock('@/lib/ui', () => ({
  getUiApi: () => ({
    message: { error: messageError },
  }),
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

// Mirrors the backend-translated AxiosError message (code 3 -> 权限不足)
const permissionDenied = () => Object.assign(new Error('权限不足'), { code: 3 })

describe('FileColumnBrowser', () => {
  beforeEach(() => {
    vi.mocked(filesApi.list).mockReset()
    messageError.mockReset()
    resetNotifyOnceCache()
  })

  it('shows a message bubble including the path when a column fails to load', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockRejectedValueOnce(permissionDenied())

    const wrapper = createWrapper('/var')
    await flushPromises()

    expect(getUiApi().message.error).toHaveBeenCalledTimes(1)
    expect(messageError.mock.calls[0]?.[0]).toContain('/var')
    expect(wrapper.text()).toContain('加载失败，点击重试')
  })

  it('only notifies once when the same path fails twice in a row', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockRejectedValueOnce(permissionDenied())
      .mockResolvedValueOnce([])
      .mockRejectedValueOnce(permissionDenied())

    const wrapper = createWrapper('/var')
    await flushPromises()
    expect(messageError).toHaveBeenCalledTimes(1)

    await (wrapper.vm as unknown as { refresh: () => Promise<void> }).refresh()
    await flushPromises()

    expect(messageError).toHaveBeenCalledTimes(1)
    expect(messageError.mock.calls[0]?.[0]).toContain('/var')
  })

  it('retries a failed column when the error placeholder is clicked', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([])
      .mockRejectedValueOnce(permissionDenied())
      .mockResolvedValueOnce([file('notes.txt')])

    const wrapper = createWrapper('/var')
    await flushPromises()

    const retry = wrapper.findAll('button').find((item) => item.text().includes('加载失败，点击重试'))
    expect(retry).toBeTruthy()
    await retry!.trigger('click')
    await flushPromises()

    expect(wrapper.text()).toContain('notes.txt')
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
    expect(wrapper.findAll('[data-file-name]')[0]!.classes()).toContain(
      'file-column-item-directory-selected',
    )
  })

  it('keeps the active directory highlighted when a file is selected', async () => {
    vi.mocked(filesApi.list)
      .mockResolvedValueOnce([directory('var')])
      .mockResolvedValueOnce([file('notes.txt')])

    const wrapper = createWrapper()
    await flushPromises()
    await wrapper.setProps({ selectedNames: ['notes.txt'], selectionPath: '/var' })

    const [activeDirectory, selectedFile] = wrapper.findAll('[data-file-name]')
    expect(activeDirectory!.attributes('aria-current')).toBe('page')
    expect(activeDirectory!.classes()).toContain('file-column-item-directory-selected')
    expect(selectedFile!.attributes('aria-selected')).toBe('true')
    expect(selectedFile!.classes()).toContain('file-column-item-file-selected')
    expect(selectedFile!.classes()).not.toContain('file-column-item-directory-selected')
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

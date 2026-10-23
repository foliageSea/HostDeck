import { enableAutoUnmount, flushPromises, shallowMount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import TextEditorView from '../index.vue'

const mocks = vi.hoisted(() => ({
  desktop: {
    activeWindowId: 'editor-2',
    setWindowBeforeClose: vi.fn(),
  },
  readFile: vi.fn().mockResolvedValue('file content'),
  writeFile: vi.fn().mockResolvedValue(undefined),
  success: vi.fn(),
}))

vi.mock('@/api/files', () => ({
  filesApi: { readFile: mocks.readFile, writeFile: mocks.writeFile },
}))
vi.mock('@/stores/desktop', () => ({ useDesktopStore: () => mocks.desktop }))
vi.mock('@/stores/settings', () => ({
  useSettingsStore: () => ({ isDark: false, editorFontFamily: 'monospace' }),
}))
vi.mock('@/lib/ui', () => ({
  getUiApi: () => ({ message: { success: mocks.success } }),
}))

enableAutoUnmount(afterEach)

function mountEditor(windowId: string) {
  return shallowMount(TextEditorView, {
    props: { windowId, connectionId: 'connection-1', path: `/${windowId}.txt` },
    global: {
      stubs: {
        NMenu: true,
        NPopover: true,
        NSpin: true,
        NResult: true,
        NModal: true,
        NSpace: true,
        NInput: true,
        NInputNumber: true,
        NButton: true,
      },
    },
  })
}

function pressSave(options: KeyboardEventInit = { ctrlKey: true }) {
  const event = new KeyboardEvent('keydown', {
    key: 's',
    cancelable: true,
    ...options,
  })
  window.dispatchEvent(event)
  return event
}

describe('TextEditor save shortcut', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.desktop.activeWindowId = 'editor-2'
  })

  it('saves only the active editor and shows one notification with multiple editors open', async () => {
    mountEditor('editor-1')
    mountEditor('editor-2')
    await flushPromises()

    expect(pressSave().defaultPrevented).toBe(true)
    await flushPromises()

    expect(mocks.writeFile).toHaveBeenCalledExactlyOnceWith(
      'connection-1',
      '/editor-2.txt',
      'file content',
    )
    expect(mocks.success).toHaveBeenCalledExactlyOnceWith('文件已保存。')

    mocks.desktop.activeWindowId = 'editor-1'
    pressSave({ metaKey: true })
    await flushPromises()

    expect(mocks.writeFile).toHaveBeenCalledTimes(2)
    expect(mocks.writeFile).toHaveBeenLastCalledWith(
      'connection-1',
      '/editor-1.txt',
      'file content',
    )
    expect(mocks.success).toHaveBeenCalledTimes(2)
  })

  it('does not save when another application is active', async () => {
    mountEditor('editor-1')
    mocks.desktop.activeWindowId = 'files-1'
    await flushPromises()

    expect(pressSave().defaultPrevented).toBe(false)
    await flushPromises()

    expect(mocks.writeFile).not.toHaveBeenCalled()
    expect(mocks.success).not.toHaveBeenCalled()
  })

  it('ignores key repeats after the first save completes', async () => {
    mountEditor('editor-2')
    await flushPromises()

    pressSave()
    await flushPromises()
    expect(pressSave({ ctrlKey: true, repeat: true }).defaultPrevented).toBe(true)
    await flushPromises()

    expect(mocks.writeFile).toHaveBeenCalledTimes(1)
    expect(mocks.success).toHaveBeenCalledTimes(1)
  })
})

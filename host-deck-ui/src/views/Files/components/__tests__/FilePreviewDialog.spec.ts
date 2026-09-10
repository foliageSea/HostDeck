import { mount } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import type { FileItem } from '@/api/files'
import FilePreviewDialog from '../FilePreviewDialog.vue'

vi.mock('@/stores/settings', () => ({
  useSettingsStore: () => ({ isDark: false }),
}))

const file: FileItem = {
  filename: 'preview.jpg',
  isDirectory: false,
  longname: '-rw-r--r-- preview.jpg',
  size: 1024,
}

function createWrapper(show = true) {
  return mount(FilePreviewDialog, {
    props: {
      connectionId: 'connection-1',
      file,
      path: '/home/media',
      show,
    },
    global: {
      stubs: {
        NModal: { template: '<div><slot /></div>' },
        FileMediaPreview: { template: '<div />' },
      },
    },
  })
}

describe('FilePreviewDialog', () => {
  it('closes the preview with space and stops the outer shortcut', () => {
    const wrapper = createWrapper()
    const outerHandler = vi.fn()
    window.addEventListener('keydown', outerHandler)

    window.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: ' ' }))

    expect(wrapper.emitted('update:show')).toEqual([[false]])
    expect(outerHandler).not.toHaveBeenCalled()
    window.removeEventListener('keydown', outerHandler)
    wrapper.unmount()
  })

  it('ignores space when the preview is hidden', () => {
    const wrapper = createWrapper(false)

    window.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: ' ' }))

    expect(wrapper.emitted('update:show')).toBeUndefined()
    wrapper.unmount()
  })
})

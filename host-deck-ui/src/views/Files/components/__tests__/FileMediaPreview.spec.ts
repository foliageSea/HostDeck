import { mount } from '@vue/test-utils'
import type { FileItem } from '@/api/files'
import FileMediaPreview from '../FileMediaPreview.vue'

const baseFile: FileItem = {
  filename: 'preview.jpg',
  isDirectory: false,
  longname: '-rw-r--r-- preview.jpg',
  size: 1024,
}

function mountPreview(
  file: FileItem,
  connectionId: string | null = 'connection-1',
  variant: 'grid' | 'list' = 'grid',
) {
  return mount(FileMediaPreview, {
    props: {
      connectionId,
      currentPath: '/home/media',
      file,
      variant,
    },
    global: {
      stubs: {
        NIcon: { template: '<span><slot /></span>' },
      },
    },
  })
}

describe('FileMediaPreview', () => {
  it('renders an image from the existing file read endpoint', () => {
    const wrapper = mountPreview(baseFile)
    const image = wrapper.get('img:not(.file-type-icon)')

    expect(image.attributes('src')).toBe(
      '/api/files/read?connectionId=connection-1&path=%2Fhome%2Fmedia%2Fpreview.jpg',
    )
    expect(image.classes()).toContain('h-[60px]')
  })

  it('renders a muted metadata-only video for its opening frame', () => {
    const wrapper = mountPreview({ ...baseFile, filename: 'clip.mp4' })
    const video = wrapper.get('video')

    expect(video.attributes('preload')).toBe('metadata')
    expect((video.element as HTMLVideoElement).muted).toBe(true)
    expect(video.attributes()).toHaveProperty('playsinline')
    expect(video.classes()).toContain('h-[60px]')
  })

  it('uses compact media dimensions in list view', () => {
    const wrapper = mountPreview(baseFile, 'connection-1', 'list')

    expect(wrapper.get('img:not(.file-type-icon)').classes()).toContain('h-[28px]')
  })

  it('falls back to the file icon when no connection is available', () => {
    const wrapper = mountPreview(baseFile, null)

    const icon = wrapper.get('img.file-type-icon')

    expect(wrapper.find('img:not(.file-type-icon)').exists()).toBe(false)
    expect(wrapper.find('video').exists()).toBe(false)
    expect(icon.attributes('src')).toContain('image-x-generic.svg')
    expect(icon.classes()).toContain('h-[60px]')
  })
})

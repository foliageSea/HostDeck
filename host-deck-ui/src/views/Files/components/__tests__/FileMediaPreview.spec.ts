import { mount } from '@vue/test-utils'
import type { FileItem } from '@/api/files'
import FileMediaPreview from '../FileMediaPreview.vue'

const baseFile: FileItem = {
  filename: 'preview.jpg',
  isDirectory: false,
  longname: '-rw-r--r-- preview.jpg',
  size: 1024,
}

function mountPreview(file: FileItem, connectionId: string | null = 'connection-1') {
  return mount(FileMediaPreview, {
    props: {
      connectionId,
      currentPath: '/home/media',
      file,
      variant: 'grid',
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
    const image = wrapper.get('img')

    expect(image.attributes('src')).toBe(
      '/api/files/read?connectionId=connection-1&path=%2Fhome%2Fmedia%2Fpreview.jpg',
    )
  })

  it('renders a muted metadata-only video for its opening frame', () => {
    const wrapper = mountPreview({ ...baseFile, filename: 'clip.mp4' })
    const video = wrapper.get('video')

    expect(video.attributes('preload')).toBe('metadata')
    expect((video.element as HTMLVideoElement).muted).toBe(true)
    expect(video.attributes()).toHaveProperty('playsinline')
  })

  it('falls back to the file icon when no connection is available', () => {
    const wrapper = mountPreview(baseFile, null)

    expect(wrapper.find('img').exists()).toBe(false)
    expect(wrapper.find('video').exists()).toBe(false)
    expect(wrapper.find('.absolute').exists()).toBe(true)
  })
})

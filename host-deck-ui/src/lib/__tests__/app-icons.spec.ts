import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  clearAppIconCache,
  preloadAppIcon,
  preloadAppIcons,
  themedAppIconMap,
} from '@/lib/app-icons'

function createImageMock(onCreate?: () => void) {
  class MockImage {
    onerror: (() => void) | null = null
    onload: (() => void) | null = null
    decoding = ''

    constructor() {
      onCreate?.()
    }

    set src(_value: string) {
      queueMicrotask(() => this.onload?.())
    }
  }

  return MockImage as unknown as typeof Image
}

describe('app icon preloading', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    clearAppIconCache()
  })

  it('preloads each unique themed icon once', async () => {
    let imageCount = 0
    vi.stubGlobal(
      'Image',
      createImageMock(() => {
        imageCount += 1
      }),
    )

    await preloadAppIcons(['terminal', 'docker', 'terminal'])
    await preloadAppIcons(['terminal', 'docker'])

    expect(imageCount).toBe(2)
  })

  it('reuses the cached promise for the same icon', () => {
    vi.stubGlobal('Image', createImageMock())

    const first = preloadAppIcon('terminal')
    const second = preloadAppIcon('terminal')

    expect(second).toBe(first)
  })

  it('resolves remote and bundled icon keys from the themed map', () => {
    expect(themedAppIconMap.opencode).toBe('/opencode.ico')
    expect(themedAppIconMap.terminal).toContain('terminal')
  })
})

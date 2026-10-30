import { afterEach, expect, it, vi } from 'vitest'
import { createDefaultWallpaperSettings, createWallpaperStyle } from '../wallpapers'

afterEach(() => vi.unstubAllEnvs())

it('keeps uploaded wallpapers on the page origin when the development proxy uses HTTP', () => {
  vi.stubEnv('VITE_DEV_PROXY_TARGET', 'http://localhost:8080')
  const settings = {
    ...createDefaultWallpaperSettings(),
    mode: 'custom' as const,
    customDataUrl: '/wallpapers/desktop.png',
    customType: 'image' as const,
  }
  for (const target of ['desktop', 'login'] as const) {
    expect(createWallpaperStyle(target, settings, false).backgroundImage).toBe(
      'url("/wallpapers/desktop.png")',
    )
  }
})

import type { CSSProperties } from 'vue'

export type WallpaperMode = 'default' | 'preset' | 'custom'
export type WallpaperCustomType = 'image' | 'video'
export type WallpaperTarget = 'desktop' | 'login'

export interface WallpaperSettings {
  mode: WallpaperMode
  presetId: string | null
  customDataUrl: string | null
  customType: WallpaperCustomType | null
  brightness: number
  contrast: number
}

export interface WallpaperPreset {
  id: string
  label: string
  background: string
}

export const wallpaperPresets: WallpaperPreset[] = []

const wallpaperPresetMap = new Map(wallpaperPresets.map((preset) => [preset.id, preset]))

function resolveWallpaperUrl(url: string): string {
  if (!url.startsWith('/')) {
    return url
  }

  const devProxyTarget = import.meta.env.DEV ? import.meta.env.VITE_DEV_PROXY_TARGET?.trim() : ''
  if (!devProxyTarget) {
    return url
  }

  try {
    return new URL(url, devProxyTarget).toString()
  } catch {
    return url
  }
}

export function createDefaultWallpaperSettings(): WallpaperSettings {
  return {
    mode: 'default',
    presetId: null,
    customDataUrl: null,
    customType: null,
    brightness: 100,
    contrast: 100,
  }
}

export function createWallpaperFilter(settings: WallpaperSettings): string {
  return `brightness(${settings.brightness}%) contrast(${settings.contrast}%)`
}

export function getDefaultWallpaperBackground(isDark: boolean): string {
  if (isDark) {
    return 'radial-gradient(circle at 12% 14%, rgba(45, 212, 191, 0.2), transparent 26%), radial-gradient(circle at 88% 12%, rgba(251, 113, 133, 0.13), transparent 24%), radial-gradient(circle at 58% 92%, rgba(56, 189, 248, 0.14), transparent 30%), linear-gradient(145deg, #111827 0%, #0b1220 48%, #030712 100%)'
  }

  return 'radial-gradient(circle at 12% 14%, rgba(13, 148, 136, 0.16), transparent 28%), radial-gradient(circle at 88% 10%, rgba(244, 63, 94, 0.1), transparent 24%), radial-gradient(circle at 60% 94%, rgba(14, 165, 233, 0.12), transparent 30%), linear-gradient(145deg, #f8fafc 0%, #e8edf2 50%, #d8e0e8 100%)'
}

export function resolveWallpaperBackground(
  _target: WallpaperTarget,
  settings: WallpaperSettings,
  isDark: boolean,
): string {
  if (settings.mode === 'custom' && settings.customDataUrl) {
    return `url("${resolveWallpaperUrl(settings.customDataUrl)}")`
  }

  if (settings.mode === 'preset' && settings.presetId) {
    return (
      wallpaperPresetMap.get(settings.presetId)?.background ?? getDefaultWallpaperBackground(isDark)
    )
  }

  return getDefaultWallpaperBackground(isDark)
}

export function createWallpaperStyle(
  target: WallpaperTarget,
  settings: WallpaperSettings,
  isDark: boolean,
): CSSProperties {
  const filter = createWallpaperFilter(settings)
  const background = resolveWallpaperBackground(target, settings, isDark)
  if (settings.mode === 'custom' && settings.customDataUrl) {
    return {
      backgroundColor: isDark ? '#020617' : '#e2e8f0',
      backgroundImage: background,
      backgroundPosition: 'center',
      backgroundRepeat: 'no-repeat',
      backgroundSize: 'cover',
      filter,
    }
  }

  return {
    background,
    filter,
  }
}

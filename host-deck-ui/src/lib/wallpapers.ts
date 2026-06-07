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
  }
  catch {
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
    return 'radial-gradient(circle at 15% 18%, rgba(14, 165, 233, 0.18), transparent 24%), radial-gradient(circle at 85% 15%, rgba(168, 85, 247, 0.18), transparent 18%), radial-gradient(circle at 50% 85%, rgba(59, 130, 246, 0.12), transparent 24%), linear-gradient(160deg, #0f172a 0%, #111827 50%, #020617 100%)'
  }

  return 'radial-gradient(circle at 15% 18%, rgba(59, 130, 246, 0.16), transparent 24%), radial-gradient(circle at 85% 15%, rgba(217, 70, 239, 0.14), transparent 18%), linear-gradient(160deg, #dbeafe 0%, #e2e8f0 50%, #cbd5e1 100%)'
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
    return wallpaperPresetMap.get(settings.presetId)?.background ?? getDefaultWallpaperBackground(isDark)
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

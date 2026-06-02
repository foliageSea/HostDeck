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

export function getDefaultWallpaperBackground(target: WallpaperTarget, isDark: boolean): string {
  if (target === 'login') {
    return 'radial-gradient(circle at 20% 20%, rgba(56, 189, 248, 0.2), transparent 24%), radial-gradient(circle at 80% 16%, rgba(168, 85, 247, 0.18), transparent 22%), linear-gradient(135deg, rgba(15, 23, 42, 0.78), rgba(2, 6, 23, 0.92))'
  }

  if (isDark) {
    return 'radial-gradient(circle at 15% 18%, rgba(14, 165, 233, 0.18), transparent 24%), radial-gradient(circle at 85% 15%, rgba(168, 85, 247, 0.18), transparent 18%), radial-gradient(circle at 50% 85%, rgba(59, 130, 246, 0.12), transparent 24%), linear-gradient(160deg, #0f172a 0%, #111827 50%, #020617 100%)'
  }

  return 'radial-gradient(circle at 15% 18%, rgba(59, 130, 246, 0.16), transparent 24%), radial-gradient(circle at 85% 15%, rgba(217, 70, 239, 0.14), transparent 18%), linear-gradient(160deg, #dbeafe 0%, #e2e8f0 50%, #cbd5e1 100%)'
}

export function resolveWallpaperBackground(
  target: WallpaperTarget,
  settings: WallpaperSettings,
  isDark: boolean,
): string {
  if (settings.mode === 'custom' && settings.customDataUrl) {
    return `url("${settings.customDataUrl}")`
  }

  if (settings.mode === 'preset' && settings.presetId) {
    return wallpaperPresetMap.get(settings.presetId)?.background ?? getDefaultWallpaperBackground(target, isDark)
  }

  return getDefaultWallpaperBackground(target, isDark)
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

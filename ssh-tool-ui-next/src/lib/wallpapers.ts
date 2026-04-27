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

export const wallpaperPresets: WallpaperPreset[] = [
  {
    id: 'aurora',
    label: '极光',
    background:
      'radial-gradient(circle at 18% 20%, rgba(34, 211, 238, 0.22), transparent 24%), radial-gradient(circle at 82% 18%, rgba(168, 85, 247, 0.2), transparent 22%), linear-gradient(145deg, #0f172a 0%, #111827 52%, #020617 100%)',
  },
  {
    id: 'sunset',
    label: '霞光',
    background:
      'radial-gradient(circle at 22% 18%, rgba(251, 146, 60, 0.24), transparent 24%), radial-gradient(circle at 78% 16%, rgba(244, 114, 182, 0.2), transparent 20%), linear-gradient(160deg, #431407 0%, #7c2d12 45%, #1e1b4b 100%)',
  },
  {
    id: 'forest',
    label: '森雾',
    background:
      'radial-gradient(circle at 20% 16%, rgba(16, 185, 129, 0.22), transparent 22%), radial-gradient(circle at 80% 14%, rgba(45, 212, 191, 0.16), transparent 18%), linear-gradient(155deg, #052e2b 0%, #0f3d32 42%, #071b1b 100%)',
  },
  {
    id: 'dawn',
    label: '晨曦',
    background:
      'radial-gradient(circle at 16% 20%, rgba(96, 165, 250, 0.22), transparent 24%), radial-gradient(circle at 84% 18%, rgba(244, 114, 182, 0.16), transparent 18%), linear-gradient(160deg, #dbeafe 0%, #e2e8f0 50%, #cbd5e1 100%)',
  },
  {
    id: 'midnight',
    label: '深夜',
    background:
      'radial-gradient(circle at 50% 12%, rgba(59, 130, 246, 0.2), transparent 20%), radial-gradient(circle at 50% 88%, rgba(14, 165, 233, 0.14), transparent 26%), linear-gradient(180deg, #020617 0%, #0f172a 60%, #111827 100%)',
  },
]

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
      backgroundSize: target === 'desktop' ? 'cover' : 'contain',
      filter,
    }
  }

  return {
    background,
    filter,
  }
}

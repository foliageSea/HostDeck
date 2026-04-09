import { computed, ref, watch } from 'vue'
import { defineStore } from 'pinia'
import {
  createDefaultWallpaperSettings,
  type WallpaperSettings,
} from '@/lib/wallpapers'

const THEME_STORAGE_KEY = 'ssh-tool-ui-next.theme'
const TERMINAL_FONT_SIZE_STORAGE_KEY = 'ssh-tool-ui-next.terminalFontSize'
const TERMINAL_FONT_FAMILY_STORAGE_KEY = 'ssh-tool-ui-next.terminalFontFamily'
const DESKTOP_WALLPAPER_STORAGE_KEY = 'ssh-tool-ui-next.desktopWallpaper'
const LOGIN_WALLPAPER_STORAGE_KEY = 'ssh-tool-ui-next.loginWallpaper'
const DEFAULT_TERMINAL_FONT_SIZE = 14
const DEFAULT_TERMINAL_FONT_FAMILY = 'Consolas, "Cascadia Mono", "Courier New", monospace'

type ThemeMode = 'dark' | 'light' | 'system'

function resolveStoredFontSize(): number {
  const value = Number.parseInt(window.localStorage.getItem(TERMINAL_FONT_SIZE_STORAGE_KEY) ?? '', 10)
  if (Number.isFinite(value) && value >= 8 && value <= 40) {
    return value
  }

  return DEFAULT_TERMINAL_FONT_SIZE
}

function resolveStoredFontFamily(): string {
  const value = window.localStorage.getItem(TERMINAL_FONT_FAMILY_STORAGE_KEY)
  if (value && value.trim()) {
    return value
  }

  return DEFAULT_TERMINAL_FONT_FAMILY
}

function resolveStoredMode(): ThemeMode {
  const value = window.localStorage.getItem(THEME_STORAGE_KEY)
  if (value === 'dark' || value === 'light' || value === 'system') {
    return value
  }

  return 'system'
}

function normalizeWallpaperSettings(value: unknown): WallpaperSettings {
  if (!value || typeof value !== 'object') {
    return createDefaultWallpaperSettings()
  }

  const candidate = value as Partial<WallpaperSettings>
  const mode = candidate.mode === 'default' || candidate.mode === 'preset' || candidate.mode === 'custom'
    ? candidate.mode
    : 'default'
  const presetId = typeof candidate.presetId === 'string' && candidate.presetId.trim() ? candidate.presetId : null
  const customDataUrl = typeof candidate.customDataUrl === 'string' && candidate.customDataUrl.trim()
    ? candidate.customDataUrl
    : null

  return {
    mode,
    presetId,
    customDataUrl,
  }
}

function resolveStoredWallpaper(storageKey: string): WallpaperSettings {
  const value = window.localStorage.getItem(storageKey)
  if (!value) {
    return createDefaultWallpaperSettings()
  }

  try {
    return normalizeWallpaperSettings(JSON.parse(value))
  }
  catch {
    return createDefaultWallpaperSettings()
  }
}

export const useSettingsStore = defineStore('settings', () => {
  const themeMode = ref<ThemeMode>(resolveStoredMode())
  const prefersDark = ref(window.matchMedia('(prefers-color-scheme: dark)').matches)
  const terminalFontSize = ref(resolveStoredFontSize())
  const terminalFontFamily = ref(resolveStoredFontFamily())
  const desktopWallpaper = ref<WallpaperSettings>(resolveStoredWallpaper(DESKTOP_WALLPAPER_STORAGE_KEY))
  const loginWallpaper = ref<WallpaperSettings>(resolveStoredWallpaper(LOGIN_WALLPAPER_STORAGE_KEY))

  const isDark = computed(() => {
    if (themeMode.value === 'system') {
      return prefersDark.value
    }

    return themeMode.value === 'dark'
  })

  const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
  const handleThemeChange = (event: MediaQueryListEvent) => {
    prefersDark.value = event.matches
  }

  if ('addEventListener' in mediaQuery) {
    mediaQuery.addEventListener('change', handleThemeChange)
  }

  watch(
    themeMode,
    (value) => {
      window.localStorage.setItem(THEME_STORAGE_KEY, value)
    },
    { immediate: true },
  )

  watch(
    terminalFontSize,
    (value) => {
      window.localStorage.setItem(TERMINAL_FONT_SIZE_STORAGE_KEY, String(value))
    },
    { immediate: true },
  )

  watch(
    terminalFontFamily,
    (value) => {
      window.localStorage.setItem(TERMINAL_FONT_FAMILY_STORAGE_KEY, value)
    },
    { immediate: true },
  )

  watch(
    desktopWallpaper,
    (value) => {
      window.localStorage.setItem(DESKTOP_WALLPAPER_STORAGE_KEY, JSON.stringify(value))
    },
    { deep: true, immediate: true },
  )

  watch(
    loginWallpaper,
    (value) => {
      window.localStorage.setItem(LOGIN_WALLPAPER_STORAGE_KEY, JSON.stringify(value))
    },
    { deep: true, immediate: true },
  )

  function toggleTheme() {
    themeMode.value = isDark.value ? 'light' : 'dark'
  }

  function setTheme(mode: ThemeMode) {
    themeMode.value = mode
  }

  function setTerminalFontSize(size: number) {
    terminalFontSize.value = Math.max(8, Math.min(40, Math.round(size)))
  }

  function setTerminalFontFamily(family: string) {
    terminalFontFamily.value = family.trim() || DEFAULT_TERMINAL_FONT_FAMILY
  }

  function resetTerminalSettings() {
    terminalFontSize.value = DEFAULT_TERMINAL_FONT_SIZE
    terminalFontFamily.value = DEFAULT_TERMINAL_FONT_FAMILY
  }

  function setDesktopWallpaper(value: WallpaperSettings) {
    desktopWallpaper.value = normalizeWallpaperSettings(value)
  }

  function setLoginWallpaper(value: WallpaperSettings) {
    loginWallpaper.value = normalizeWallpaperSettings(value)
  }

  function resetDesktopWallpaper() {
    desktopWallpaper.value = createDefaultWallpaperSettings()
  }

  function resetLoginWallpaper() {
    loginWallpaper.value = createDefaultWallpaperSettings()
  }

  return {
    desktopWallpaper,
    isDark,
    loginWallpaper,
    resetDesktopWallpaper,
    resetLoginWallpaper,
    setTheme,
    setDesktopWallpaper,
    setLoginWallpaper,
    resetTerminalSettings,
    setTerminalFontFamily,
    setTerminalFontSize,
    terminalFontFamily,
    terminalFontSize,
    themeMode,
    toggleTheme,
  }
})

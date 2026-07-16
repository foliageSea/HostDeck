import { computed, ref, watch } from 'vue'
import { defineStore } from 'pinia'
import { settingsApi } from '@/api/settings'
import {
  createDefaultWallpaperSettings,
  type WallpaperSettings,
  type WallpaperTarget,
} from '@/lib/wallpapers'

const THEME_STORAGE_KEY = 'host-deck-ui.theme'
const PRIMARY_COLOR_STORAGE_KEY = 'host-deck-ui.primaryColor'
const TERMINAL_FONT_SIZE_STORAGE_KEY = 'host-deck-ui.terminalFontSize'
const TERMINAL_FONT_FAMILY_STORAGE_KEY = 'host-deck-ui.terminalFontFamily'
const EDITOR_FONT_SIZE_STORAGE_KEY = 'host-deck-ui.editorFontSize'
const EDITOR_FONT_FAMILY_STORAGE_KEY = 'host-deck-ui.editorFontFamily'
const DESKTOP_WALLPAPER_STORAGE_KEY = 'host-deck-ui.desktopWallpaper'
const LOGIN_WALLPAPER_STORAGE_KEY = 'host-deck-ui.loginWallpaper'
const WINDOW_CONTROLS_STYLE_STORAGE_KEY = 'host-deck-ui.windowControlsStyle'
const CORNER_STYLE_STORAGE_KEY = 'host-deck-ui.cornerStyle'
const DOCK_AUTO_HIDE_STORAGE_KEY = 'host-deck-ui.dockAutoHide'

const DEFAULT_TERMINAL_FONT_SIZE = 14
const DEFAULT_TERMINAL_FONT_FAMILY = '"Maple Mono"'
const DEFAULT_EDITOR_FONT_SIZE = 14
const DEFAULT_EDITOR_FONT_FAMILY = '"Maple Mono"'
const DEFAULT_PRIMARY_COLOR = '#0891b2'
const WALLPAPER_PERSIST_DEBOUNCE_MS = 300

type ThemeMode = 'dark' | 'light' | 'system'
type WindowControlsStyle = 'mac' | 'win'
export type CornerStyle = 'square' | 'soft' | 'rounded'

function normalizeCornerStyle(value: unknown): CornerStyle {
  if (value === 'square' || value === 'soft' || value === 'rounded') {
    return value
  }

  return 'rounded'
}

function resolveStoredWindowControlsStyle(): WindowControlsStyle {
  const value = window.localStorage.getItem(WINDOW_CONTROLS_STYLE_STORAGE_KEY)
  if (value === 'mac' || value === 'win') {
    return value
  }

  return 'mac'
}

function resolveStoredCornerStyle(): CornerStyle {
  return normalizeCornerStyle(window.localStorage.getItem(CORNER_STYLE_STORAGE_KEY))
}

function resolveStoredDockAutoHide(): boolean {
  return window.localStorage.getItem(DOCK_AUTO_HIDE_STORAGE_KEY) === 'true'
}

function normalizeWallpaperEffectValue(value: unknown): number {
  const numericValue = typeof value === 'number' ? value : Number(value)
  if (!Number.isFinite(numericValue)) {
    return 100
  }

  return Math.max(50, Math.min(150, Math.round(numericValue)))
}

function resolveStoredFontSize(): number {
  const value = Number.parseInt(
    window.localStorage.getItem(TERMINAL_FONT_SIZE_STORAGE_KEY) ?? '',
    10,
  )
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

function resolveStoredEditorFontSize(): number {
  const value = Number.parseInt(window.localStorage.getItem(EDITOR_FONT_SIZE_STORAGE_KEY) ?? '', 10)
  if (Number.isFinite(value) && value >= 8 && value <= 40) {
    return value
  }

  return DEFAULT_EDITOR_FONT_SIZE
}

function resolveStoredEditorFontFamily(): string {
  const value = window.localStorage.getItem(EDITOR_FONT_FAMILY_STORAGE_KEY)
  if (value && value.trim()) {
    return value
  }

  return DEFAULT_EDITOR_FONT_FAMILY
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
  const mode =
    candidate.mode === 'default' || candidate.mode === 'preset' || candidate.mode === 'custom'
      ? candidate.mode
      : 'default'
  const presetId =
    typeof candidate.presetId === 'string' && candidate.presetId.trim() ? candidate.presetId : null
  const customDataUrl =
    typeof candidate.customDataUrl === 'string' && candidate.customDataUrl.trim()
      ? candidate.customDataUrl
      : null
  const customType =
    candidate.customType === 'image' || candidate.customType === 'video'
      ? candidate.customType
      : customDataUrl
        ? 'image'
        : null
  const brightness = normalizeWallpaperEffectValue(candidate.brightness)
  const contrast = normalizeWallpaperEffectValue(candidate.contrast)

  return {
    mode,
    presetId,
    customDataUrl,
    customType,
    brightness,
    contrast,
  }
}

function normalizePrimaryColor(value: unknown): string {
  if (typeof value !== 'string') {
    return DEFAULT_PRIMARY_COLOR
  }

  const color = value.trim()
  if (/^#[\da-f]{6}$/i.test(color)) {
    return color.toLowerCase()
  }

  return DEFAULT_PRIMARY_COLOR
}

function resolveStoredPrimaryColor(): string {
  return normalizePrimaryColor(window.localStorage.getItem(PRIMARY_COLOR_STORAGE_KEY))
}

function resolveStoredWallpaper(storageKey: string): WallpaperSettings {
  const value = window.localStorage.getItem(storageKey)
  if (!value) {
    return createDefaultWallpaperSettings()
  }

  try {
    return normalizeWallpaperSettings(JSON.parse(value))
  } catch {
    return createDefaultWallpaperSettings()
  }
}

function serializeWallpaperSettings(value: WallpaperSettings): WallpaperSettings {
  return value
}

export const useSettingsStore = defineStore('settings', () => {
  const themeMode = ref<ThemeMode>(resolveStoredMode())
  const primaryColor = ref(resolveStoredPrimaryColor())
  const prefersDark = ref(window.matchMedia('(prefers-color-scheme: dark)').matches)
  const terminalFontSize = ref(resolveStoredFontSize())
  const terminalFontFamily = ref(resolveStoredFontFamily())
  const editorFontSize = ref(resolveStoredEditorFontSize())
  const editorFontFamily = ref(resolveStoredEditorFontFamily())
  const windowControlsStyle = ref<WindowControlsStyle>(resolveStoredWindowControlsStyle())
  const cornerStyle = ref<CornerStyle>(resolveStoredCornerStyle())
  const dockAutoHide = ref(resolveStoredDockAutoHide())
  const desktopWallpaper = ref<WallpaperSettings>(
    resolveStoredWallpaper(DESKTOP_WALLPAPER_STORAGE_KEY),
  )
  const loginWallpaper = computed(() => desktopWallpaper.value)
  const isInitializing = ref(false)
  const hasInitialized = ref(false)
  const suspendWallpaperPersistence = ref(false)
  let wallpaperPersistTimer: number | null = null

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

  async function syncWallpaperStorage(target: WallpaperTarget, value: WallpaperSettings) {
    window.localStorage.setItem(
      target === 'desktop' ? DESKTOP_WALLPAPER_STORAGE_KEY : LOGIN_WALLPAPER_STORAGE_KEY,
      JSON.stringify(serializeWallpaperSettings(value)),
    )

    if (target === 'desktop') {
      window.localStorage.setItem(
        LOGIN_WALLPAPER_STORAGE_KEY,
        JSON.stringify(serializeWallpaperSettings(value)),
      )
    }
  }

  async function persistWallpapers() {
    if (suspendWallpaperPersistence.value) {
      return
    }

    await settingsApi.saveUiSettings({
      desktopWallpaper: serializeWallpaperSettings(desktopWallpaper.value),
      loginWallpaper: serializeWallpaperSettings(desktopWallpaper.value),
    })
  }

  function scheduleWallpaperPersistence() {
    if (wallpaperPersistTimer !== null) {
      window.clearTimeout(wallpaperPersistTimer)
    }

    wallpaperPersistTimer = window.setTimeout(() => {
      wallpaperPersistTimer = null
      void persistWallpapers()
    }, WALLPAPER_PERSIST_DEBOUNCE_MS)
  }

  async function initialize() {
    if (isInitializing.value || hasInitialized.value) {
      return
    }

    isInitializing.value = true
    try {
      const data = await settingsApi.getUiSettings()
      suspendWallpaperPersistence.value = true
      if (data.desktopWallpaper) {
        desktopWallpaper.value = normalizeWallpaperSettings(data.desktopWallpaper)
      } else if (data.loginWallpaper) {
        desktopWallpaper.value = normalizeWallpaperSettings(data.loginWallpaper)
      }
    } finally {
      suspendWallpaperPersistence.value = false
      isInitializing.value = false
      hasInitialized.value = true
    }
  }

  watch(
    themeMode,
    (value) => {
      window.localStorage.setItem(THEME_STORAGE_KEY, value)
    },
    { immediate: true },
  )

  watch(
    primaryColor,
    (value) => {
      window.localStorage.setItem(PRIMARY_COLOR_STORAGE_KEY, normalizePrimaryColor(value))
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
    editorFontSize,
    (value) => {
      window.localStorage.setItem(EDITOR_FONT_SIZE_STORAGE_KEY, String(value))
    },
    { immediate: true },
  )

  watch(
    editorFontFamily,
    (value) => {
      window.localStorage.setItem(EDITOR_FONT_FAMILY_STORAGE_KEY, value)
    },
    { immediate: true },
  )

  watch(
    windowControlsStyle,
    (value) => {
      window.localStorage.setItem(WINDOW_CONTROLS_STYLE_STORAGE_KEY, value)
    },
    { immediate: true },
  )

  watch(
    cornerStyle,
    (value) => {
      window.localStorage.setItem(CORNER_STYLE_STORAGE_KEY, normalizeCornerStyle(value))
    },
    { immediate: true },
  )

  watch(
    dockAutoHide,
    (value) => {
      window.localStorage.setItem(DOCK_AUTO_HIDE_STORAGE_KEY, String(value))
    },
    { immediate: true },
  )

  watch(
    desktopWallpaper,
    (value) => {
      void syncWallpaperStorage('desktop', value)
      if (hasInitialized.value) {
        scheduleWallpaperPersistence()
      }
    },
    { deep: true, immediate: true },
  )

  function toggleTheme() {
    themeMode.value = isDark.value ? 'light' : 'dark'
  }

  function setTheme(mode: ThemeMode) {
    themeMode.value = mode
  }

  function setPrimaryColor(color: string) {
    primaryColor.value = normalizePrimaryColor(color)
  }

  function setWindowControlsStyle(style: WindowControlsStyle) {
    windowControlsStyle.value = style
  }

  function setCornerStyle(style: CornerStyle) {
    cornerStyle.value = normalizeCornerStyle(style)
  }

  function setDockAutoHide(value: boolean) {
    dockAutoHide.value = value
  }

  function resetPrimaryColor() {
    primaryColor.value = DEFAULT_PRIMARY_COLOR
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

  function setEditorFontSize(size: number) {
    editorFontSize.value = Math.max(8, Math.min(40, Math.round(size)))
  }

  function setEditorFontFamily(family: string) {
    editorFontFamily.value = family.trim() || DEFAULT_EDITOR_FONT_FAMILY
  }

  function resetEditorSettings() {
    editorFontSize.value = DEFAULT_EDITOR_FONT_SIZE
    editorFontFamily.value = DEFAULT_EDITOR_FONT_FAMILY
  }

  function setDesktopWallpaper(value: WallpaperSettings) {
    desktopWallpaper.value = normalizeWallpaperSettings(value)
  }

  function setLoginWallpaper(value: WallpaperSettings) {
    desktopWallpaper.value = normalizeWallpaperSettings(value)
  }

  function resetDesktopWallpaper() {
    desktopWallpaper.value = createDefaultWallpaperSettings()
  }

  function resetLoginWallpaper() {
    desktopWallpaper.value = createDefaultWallpaperSettings()
  }

  return {
    cornerStyle,
    desktopWallpaper,
    dockAutoHide,
    editorFontFamily,
    editorFontSize,
    initialize,
    isDark,
    isInitializing,
    loginWallpaper,
    primaryColor,
    resetDesktopWallpaper,
    resetEditorSettings,
    resetLoginWallpaper,
    resetPrimaryColor,
    setTheme,
    setDesktopWallpaper,
    setEditorFontFamily,
    setEditorFontSize,
    setLoginWallpaper,
    setCornerStyle,
    setDockAutoHide,
    setPrimaryColor,
    setWindowControlsStyle,
    resetTerminalSettings,
    setTerminalFontFamily,
    setTerminalFontSize,
    terminalFontFamily,
    terminalFontSize,
    themeMode,
    toggleTheme,
    windowControlsStyle,
  }
})

import { computed, ref, watch } from 'vue'
import { defineStore } from 'pinia'
import {
  createDefaultWallpaperSettings,
  type WallpaperSettings,
  type WallpaperTarget,
} from '@/lib/wallpapers'
import {
  deleteStoredWallpaperDataUrl,
  getStoredWallpaperDataUrl,
  setStoredWallpaperDataUrl,
} from '@/lib/wallpaper-storage'

const THEME_STORAGE_KEY = 'ssh-tool-ui-next.theme'
const PRIMARY_COLOR_STORAGE_KEY = 'ssh-tool-ui-next.primaryColor'
const TERMINAL_FONT_SIZE_STORAGE_KEY = 'ssh-tool-ui-next.terminalFontSize'
const TERMINAL_FONT_FAMILY_STORAGE_KEY = 'ssh-tool-ui-next.terminalFontFamily'
const EDITOR_FONT_SIZE_STORAGE_KEY = 'ssh-tool-ui-next.editorFontSize'
const EDITOR_FONT_FAMILY_STORAGE_KEY = 'ssh-tool-ui-next.editorFontFamily'
const DESKTOP_WALLPAPER_STORAGE_KEY = 'ssh-tool-ui-next.desktopWallpaper'
const LOGIN_WALLPAPER_STORAGE_KEY = 'ssh-tool-ui-next.loginWallpaper'
const DEFAULT_TERMINAL_FONT_SIZE = 14
const DEFAULT_TERMINAL_FONT_FAMILY = 'Consolas, "Cascadia Mono", "Courier New", monospace'
const DEFAULT_EDITOR_FONT_SIZE = 14
const DEFAULT_EDITOR_FONT_FAMILY = 'Consolas, "Cascadia Mono", "Courier New", monospace'
const DEFAULT_PRIMARY_COLOR = '#0891b2'

type ThemeMode = 'dark' | 'light' | 'system'

function normalizeWallpaperEffectValue(value: unknown): number {
  const numericValue = typeof value === 'number' ? value : Number(value)
  if (!Number.isFinite(numericValue)) {
    return 100
  }

  return Math.max(50, Math.min(150, Math.round(numericValue)))
}

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
  const mode = candidate.mode === 'default' || candidate.mode === 'preset' || candidate.mode === 'custom'
    ? candidate.mode
    : 'default'
  const presetId = typeof candidate.presetId === 'string' && candidate.presetId.trim() ? candidate.presetId : null
  const customDataUrl = typeof candidate.customDataUrl === 'string' && candidate.customDataUrl.trim()
    ? candidate.customDataUrl
    : null
  const customType = candidate.customType === 'image' || candidate.customType === 'video'
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
  }
  catch {
    return createDefaultWallpaperSettings()
  }
}

function serializeWallpaperSettings(value: WallpaperSettings): WallpaperSettings {
  if (value.mode !== 'custom') {
    return value
  }

  return {
    ...value,
    customDataUrl: null,
  }
}

export const useSettingsStore = defineStore('settings', () => {
  const themeMode = ref<ThemeMode>(resolveStoredMode())
  const primaryColor = ref(resolveStoredPrimaryColor())
  const prefersDark = ref(window.matchMedia('(prefers-color-scheme: dark)').matches)
  const terminalFontSize = ref(resolveStoredFontSize())
  const terminalFontFamily = ref(resolveStoredFontFamily())
  const editorFontSize = ref(resolveStoredEditorFontSize())
  const editorFontFamily = ref(resolveStoredEditorFontFamily())
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

  async function syncWallpaperStorage(target: WallpaperTarget, value: WallpaperSettings) {
    window.localStorage.setItem(
      target === 'desktop' ? DESKTOP_WALLPAPER_STORAGE_KEY : LOGIN_WALLPAPER_STORAGE_KEY,
      JSON.stringify(serializeWallpaperSettings(value)),
    )

    if (value.mode === 'custom' && value.customDataUrl) {
      await setStoredWallpaperDataUrl(target, value.customDataUrl)
      return
    }

    if (value.mode === 'custom') {
      return
    }

    await deleteStoredWallpaperDataUrl(target)
  }

  async function hydrateCustomWallpaper(target: WallpaperTarget) {
    const wallpaper = target === 'desktop' ? desktopWallpaper : loginWallpaper
    if (wallpaper.value.mode !== 'custom') {
      return
    }

    if (wallpaper.value.customDataUrl) {
      await setStoredWallpaperDataUrl(target, wallpaper.value.customDataUrl)
      return
    }

    const storedDataUrl = await getStoredWallpaperDataUrl(target)
    if (!storedDataUrl) {
      return
    }

    wallpaper.value = {
      ...wallpaper.value,
      customDataUrl: storedDataUrl,
    }
  }

  void hydrateCustomWallpaper('desktop')
  void hydrateCustomWallpaper('login')

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
    desktopWallpaper,
    (value) => {
      void syncWallpaperStorage('desktop', value)
    },
    { deep: true, immediate: true },
  )

  watch(
    loginWallpaper,
    (value) => {
      void syncWallpaperStorage('login', value)
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
    editorFontFamily,
    editorFontSize,
    isDark,
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
    setPrimaryColor,
    resetTerminalSettings,
    setTerminalFontFamily,
    setTerminalFontSize,
    terminalFontFamily,
    terminalFontSize,
    themeMode,
    toggleTheme,
  }
})

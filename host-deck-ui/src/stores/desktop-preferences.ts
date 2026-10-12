import { onScopeDispose, toRefs, watch } from 'vue'
import { defineStore } from 'pinia'
import {
  createDesktopPreferences,
  createDefaultWindowSwitchShortcut,
  createDefaultWindowSwitcherToggleShortcut,
  normalizeKeyboardShortcut,
  type KeyboardShortcut,
} from '@host-deck/webos'

export type CornerStyle = 'square' | 'soft' | 'rounded'

export function normalizeCornerStyle(value: unknown): CornerStyle {
  return value === 'square' || value === 'soft' || value === 'rounded' ? value : 'rounded'
}

/** Local desktop appearance only: no HTTP, terminal or editor settings. */
export const useDesktopPreferencesStore = defineStore('desktopPreferences', () => {
  const storage = window.localStorage
  function shortcut(key: string, fallback: KeyboardShortcut) {
    try {
      return normalizeKeyboardShortcut(
        JSON.parse(storage.getItem(`host-deck-ui.${key}`) ?? 'null'),
        fallback,
      )
    } catch {
      return fallback
    }
  }
  const controlsStyle = storage.getItem('host-deck-ui.windowControlsStyle')
  const preferences = createDesktopPreferences({
    windowControlsStyle:
      controlsStyle === 'mac' || controlsStyle === 'win'
        ? controlsStyle
        : /Mac|iPhone|iPad|iPod/i.test(`${navigator.platform} ${navigator.userAgent}`)
          ? 'mac'
          : 'win',
    windowBlur: storage.getItem('host-deck-ui.windowBlur') === 'true',
    darkWindowBorder: storage.getItem('host-deck-ui.darkWindowBorder') !== 'false',
    cornerStyle: normalizeCornerStyle(storage.getItem('host-deck-ui.cornerStyle')),
    dockAutoHide: storage.getItem('host-deck-ui.dockAutoHide') === 'true',
    windowSwitchShortcut: shortcut('windowSwitchShortcut', createDefaultWindowSwitchShortcut()),
    windowSwitcherToggleShortcut: shortcut(
      'windowSwitcherToggleShortcut',
      createDefaultWindowSwitcherToggleShortcut(),
    ),
  })
  const keys = [
    'windowControlsStyle',
    'windowBlur',
    'darkWindowBorder',
    'cornerStyle',
    'dockAutoHide',
    'windowSwitchShortcut',
    'windowSwitcherToggleShortcut',
  ] as const
  const stops = keys.map((key) =>
    watch(
      () => preferences[key],
      (value) => {
        try {
          storage.setItem(
            `host-deck-ui.${key}`,
            typeof value === 'object' ? JSON.stringify(value) : String(value),
          )
        } catch {
          /* Optional persistence. */
        }
      },
      { deep: true, immediate: true },
    ),
  )
  onScopeDispose(() => stops.forEach((stop) => stop()))
  const {
    windowControlsStyle,
    windowBlur,
    darkWindowBorder,
    cornerStyle,
    dockAutoHide,
    windowSwitchShortcut,
    windowSwitcherToggleShortcut,
  } = toRefs(preferences)
  return {
    windowControlsStyle,
    windowBlur,
    darkWindowBorder,
    cornerStyle,
    dockAutoHide,
    windowSwitchShortcut,
    windowSwitcherToggleShortcut,
    setWindowControlsStyle(value: 'mac' | 'win') {
      preferences.windowControlsStyle = value
    },
    setWindowBlur(value: boolean) {
      preferences.windowBlur = value
    },
    setDarkWindowBorder(value: boolean) {
      preferences.darkWindowBorder = value
    },
    setCornerStyle(value: CornerStyle) {
      preferences.cornerStyle = normalizeCornerStyle(value)
    },
    setDockAutoHide(value: boolean) {
      preferences.dockAutoHide = value
    },
    setWindowSwitchShortcut(value: KeyboardShortcut) {
      preferences.windowSwitchShortcut = normalizeKeyboardShortcut(value)
    },
    resetWindowSwitchShortcut() {
      preferences.windowSwitchShortcut = createDefaultWindowSwitchShortcut()
    },
    setWindowSwitcherToggleShortcut(value: KeyboardShortcut) {
      preferences.windowSwitcherToggleShortcut = normalizeKeyboardShortcut(
        value,
        createDefaultWindowSwitcherToggleShortcut(),
      )
    },
    resetWindowSwitcherToggleShortcut() {
      preferences.windowSwitcherToggleShortcut = createDefaultWindowSwitcherToggleShortcut()
    },
  }
})

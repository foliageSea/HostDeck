import { computed, reactive } from 'vue'
import {
  createDefaultWindowSwitchShortcut,
  createDefaultWindowSwitcherToggleShortcut,
} from './keyboard-shortcut'
import type { KeyboardShortcut } from './keyboard-shortcut'

export type DockPosition = 'left' | 'right' | 'bottom'

export interface DesktopPreferences {
  isDark: boolean
  primaryColor: string
  windowControlsStyle: 'mac' | 'win'
  windowBlur: boolean
  darkWindowBorder: boolean
  cornerStyle: 'square' | 'soft' | 'rounded'
  dockAutoHide: boolean
  dockPosition: DockPosition
  windowSwitchShortcut: KeyboardShortcut
  windowSwitcherToggleShortcut: KeyboardShortcut
}

export function createDesktopPreferences(initial: Partial<DesktopPreferences> = {}) {
  return reactive<DesktopPreferences>({
    isDark: false,
    primaryColor: '#0891b2',
    windowControlsStyle:
      typeof navigator !== 'undefined' && /Mac|iPhone|iPad/i.test(navigator.platform)
        ? 'mac'
        : 'win',
    windowBlur: false,
    darkWindowBorder: true,
    cornerStyle: 'rounded',
    dockAutoHide: false,
    dockPosition: 'left',
    windowSwitchShortcut: createDefaultWindowSwitchShortcut(),
    windowSwitcherToggleShortcut: createDefaultWindowSwitcherToggleShortcut(),
    ...initial,
  })
}

export function desktopThemeStyle(preferences: DesktopPreferences) {
  return computed(() => {
    const color = /^#[\da-f]{6}$/i.test(preferences.primaryColor)
      ? preferences.primaryColor
      : '#0891b2'
    const numeric = Number.parseInt(color.slice(1), 16)
    const rgb = `${(numeric >> 16) & 255}, ${(numeric >> 8) & 255}, ${numeric & 255}`
    return {
      '--app-primary-color': preferences.primaryColor,
      '--app-primary-rgb': rgb,
      '--app-primary-border': `rgba(${rgb}, 0.55)`,
      '--app-primary-border-strong': `rgba(${rgb}, 0.72)`,
      '--app-radius-card':
        preferences.cornerStyle === 'square'
          ? '0px'
          : preferences.cornerStyle === 'soft'
            ? '10px'
            : '18px',
      '--app-radius-surface':
        preferences.cornerStyle === 'square'
          ? '0px'
          : preferences.cornerStyle === 'soft'
            ? '8px'
            : '16px',
      '--app-radius-item':
        preferences.cornerStyle === 'square'
          ? '0px'
          : preferences.cornerStyle === 'soft'
            ? '6px'
            : '12px',
      '--app-radius-control':
        preferences.cornerStyle === 'square'
          ? '0px'
          : preferences.cornerStyle === 'soft'
            ? '6px'
            : '10px',
    }
  })
}

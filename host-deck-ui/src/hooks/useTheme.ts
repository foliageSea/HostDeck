import { computed, watchEffect } from 'vue'
import { darkTheme, type GlobalThemeOverrides } from 'naive-ui'
import { useSettingsStore } from '@/stores/settings'

function hexToRgb(color: string) {
  const normalizedColor = color.replace('#', '')
  const value = Number.parseInt(normalizedColor, 16)

  return `${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}`
}

export function useTheme() {
  const settingsStore = useSettingsStore()
  const theme = computed(() => (settingsStore.isDark ? darkTheme : null))
  const radiusVars = computed(() => {
    switch (settingsStore.cornerStyle) {
      case 'square':
        return {
          buttonTiny: '0px',
          buttonSmall: '0px',
          buttonMedium: '0px',
          buttonLarge: '0px',
          card: '0px',
          surface: '0px',
          item: '0px',
          control: '0px',
        }
      case 'soft':
        return {
          buttonTiny: '4px',
          buttonSmall: '6px',
          buttonMedium: '6px',
          buttonLarge: '8px',
          card: '10px',
          surface: '8px',
          item: '6px',
          control: '6px',
        }
      case 'rounded':
        return {
          buttonTiny: '8px',
          buttonSmall: '10px',
          buttonMedium: '10px',
          buttonLarge: '12px',
          card: '18px',
          surface: '16px',
          item: '12px',
          control: '10px',
        }
    }
  })
  const themeOverrides = computed<GlobalThemeOverrides>(() => ({
    common: {
      fontFamily:
        "'Maple Mono', Inter, 'Segoe UI', system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
      fontFamilyMono: "'Maple Mono', Consolas, 'Cascadia Mono', 'Courier New', monospace",
      primaryColor: settingsStore.primaryColor,
      primaryColorHover: settingsStore.primaryColor,
      primaryColorPressed: settingsStore.primaryColor,
      primaryColorSuppl: settingsStore.primaryColor,
    },
    Button: {
      borderRadiusTiny: radiusVars.value.buttonTiny,
      borderRadiusSmall: radiusVars.value.buttonSmall,
      borderRadiusMedium: radiusVars.value.buttonMedium,
      borderRadiusLarge: radiusVars.value.buttonLarge,
    },
    Card: {
      borderRadius: radiusVars.value.card,
    },
  }))

  watchEffect(() => {
    const primaryRgb = hexToRgb(settingsStore.primaryColor)

    document.documentElement.dataset.theme = settingsStore.isDark ? 'dark' : 'light'
    document.documentElement.dataset.cornerStyle = settingsStore.cornerStyle
    document.documentElement.dataset.electron = window.hostDeck?.window ? 'true' : 'false'
    if (window.hostDeck?.shellMode) {
      document.documentElement.dataset.electronShell = window.hostDeck.shellMode
    } else {
      delete document.documentElement.dataset.electronShell
    }
    document.documentElement.style.setProperty('--app-primary-color', settingsStore.primaryColor)
    document.documentElement.style.setProperty('--app-primary-rgb', primaryRgb)
    document.documentElement.style.setProperty('--app-primary-border', `rgba(${primaryRgb}, 0.55)`)
    document.documentElement.style.setProperty(
      '--app-primary-border-strong',
      `rgba(${primaryRgb}, 0.72)`,
    )
    document.documentElement.style.setProperty('--app-primary-soft', `rgba(${primaryRgb}, 0.16)`)
    document.documentElement.style.setProperty(
      '--app-primary-soft-strong',
      `rgba(${primaryRgb}, 0.24)`,
    )
    document.documentElement.style.setProperty('--app-radius-card', radiusVars.value.card)
    document.documentElement.style.setProperty('--app-radius-surface', radiusVars.value.surface)
    document.documentElement.style.setProperty('--app-radius-item', radiusVars.value.item)
    document.documentElement.style.setProperty('--app-radius-control', radiusVars.value.control)
    document.documentElement.style.setProperty('--app-radius-button', radiusVars.value.buttonMedium)
  })

  return { theme, themeOverrides }
}

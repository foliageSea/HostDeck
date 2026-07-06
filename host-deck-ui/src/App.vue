<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, watch, watchEffect } from 'vue'
import {
  darkTheme,
  dateZhCN,
  NConfigProvider,
  NDialogProvider,
  NGlobalStyle,
  NLoadingBarProvider,
  NMessageProvider,
  NNotificationProvider,
  zhCN,
  type GlobalThemeOverrides,
} from 'naive-ui'
import UiApiBridge from '@/components/common/UiApiBridge.vue'
import DesktopShell from '@/components/os/DesktopShell.vue'
import LoginScreen from '@/components/os/LoginScreen.vue'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import { useUploadCenterStore } from '@/stores/upload-center'

const sshStore = useSshStore()
const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const uploadCenterStore = useUploadCenterStore()

const theme = computed(() => (settingsStore.isDark ? darkTheme : null))
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
}))

function hexToRgb(color: string) {
  const normalizedColor = color.replace('#', '')
  const value = Number.parseInt(normalizedColor, 16)

  return `${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}`
}

watchEffect(() => {
  const primaryRgb = hexToRgb(settingsStore.primaryColor)

  document.documentElement.dataset.theme = settingsStore.isDark ? 'dark' : 'light'
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
})

watch(
  () => sshStore.isConnected,
  (isConnected) => {
    if (!isConnected) {
      desktopStore.reset()
    }
  },
)

function handleBeforeUnload(event: BeforeUnloadEvent) {
  if (uploadCenterStore.activeTaskCount <= 0) {
    return
  }

  event.preventDefault()
  event.returnValue = ''
}

onMounted(() => {
  window.addEventListener('beforeunload', handleBeforeUnload)
})

onBeforeUnmount(() => {
  window.removeEventListener('beforeunload', handleBeforeUnload)
})
</script>

<template>
  <NConfigProvider
    :theme="theme"
    :theme-overrides="themeOverrides"
    :locale="zhCN"
    :date-locale="dateZhCN"
  >
    <NLoadingBarProvider>
      <NDialogProvider>
        <NNotificationProvider>
          <NMessageProvider>
            <NGlobalStyle />
            <UiApiBridge />
            <div class="app-root min-h-screen">
              <Transition name="fade" mode="out-in">
                <DesktopShell v-if="sshStore.isConnected" />
                <LoginScreen v-else />
              </Transition>
            </div>
          </NMessageProvider>
        </NNotificationProvider>
      </NDialogProvider>
    </NLoadingBarProvider>
  </NConfigProvider>
</template>

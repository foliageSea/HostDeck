<script setup lang="ts">
import { computed, watch, watchEffect } from 'vue'
import { darkTheme, dateZhCN, NConfigProvider, NDialogProvider, NGlobalStyle, NLoadingBarProvider, NMessageProvider, NNotificationProvider, zhCN, type GlobalThemeOverrides } from 'naive-ui'
import UiApiBridge from '@/components/common/UiApiBridge.vue'
import DesktopShell from '@/components/os/DesktopShell.vue'
import LoginScreen from '@/components/os/LoginScreen.vue'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

const sshStore = useSshStore()
const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()

const theme = computed(() => (settingsStore.isDark ? darkTheme : null))
const themeOverrides = computed<GlobalThemeOverrides>(() => ({
  common: {
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
  document.documentElement.style.setProperty('--app-primary-color', settingsStore.primaryColor)
  document.documentElement.style.setProperty('--app-primary-rgb', primaryRgb)
  document.documentElement.style.setProperty('--app-primary-border', `rgba(${primaryRgb}, 0.55)`)
  document.documentElement.style.setProperty('--app-primary-border-strong', `rgba(${primaryRgb}, 0.72)`)
  document.documentElement.style.setProperty('--app-primary-soft', `rgba(${primaryRgb}, 0.16)`)
  document.documentElement.style.setProperty('--app-primary-soft-strong', `rgba(${primaryRgb}, 0.24)`)
})

watch(
  () => sshStore.isConnected,
  (isConnected) => {
    if (!isConnected) {
      desktopStore.reset()
    }
  },
)
</script>

<template>
  <NConfigProvider :theme="theme" :theme-overrides="themeOverrides" :locale="zhCN" :date-locale="dateZhCN">
    <NLoadingBarProvider>
      <NDialogProvider>
        <NNotificationProvider>
          <NMessageProvider>
            <NGlobalStyle />
            <UiApiBridge />
            <div class="min-h-screen">
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

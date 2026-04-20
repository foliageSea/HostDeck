<script setup lang="ts">
import { computed, onMounted, watch, watchEffect } from 'vue'
import { darkTheme, dateZhCN, NConfigProvider, NDialogProvider, NGlobalStyle, NLoadingBarProvider, NMessageProvider, NNotificationProvider, zhCN } from 'naive-ui'
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

watchEffect(() => {
  document.documentElement.dataset.theme = settingsStore.isDark ? 'dark' : 'light'
})

watch(
  () => sshStore.isConnected,
  (isConnected) => {
    if (!isConnected) {
      desktopStore.reset()
    }
  },
)

onMounted(() => {
  void sshStore.restoreSession()
})
</script>

<template>
  <NConfigProvider :theme="theme" :locale="zhCN" :date-locale="dateZhCN">
    <NLoadingBarProvider>
      <NDialogProvider>
        <NNotificationProvider>
          <NMessageProvider>
            <NGlobalStyle />
            <UiApiBridge />
            <div class="min-h-screen">
              <div v-if="!sshStore.isReady" class="grid min-h-screen place-items-center text-[0.95rem] text-[rgba(100,116,139,0.9)]">
                正在恢复连接状态...
              </div>
              <Transition v-else name="fade" mode="out-in">
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

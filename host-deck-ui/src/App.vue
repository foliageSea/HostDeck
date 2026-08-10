<script setup lang="ts">
import { onBeforeUnmount, onMounted, watch } from 'vue'
import {
  dateZhCN,
  NConfigProvider,
  NDialogProvider,
  NGlobalStyle,
  NLoadingBarProvider,
  NMessageProvider,
  NNotificationProvider,
  zhCN,
} from 'naive-ui'
import UiApiBridge from '@/components/common/UiApiBridge.vue'
import DesktopShell from '@/components/os/DesktopShell.vue'
import LoginScreen from '@/components/os/LoginScreen.vue'
import AccessLoginScreen from '@/components/os/AccessLoginScreen.vue'
import { useAccessStore } from '@/stores/access'
import { useDesktopStore } from '@/stores/desktop'
import { useSshStore } from '@/stores/ssh'
import { useUploadCenterStore } from '@/stores/upload-center'
import { useSuppressNativeTitles } from '@/hooks/useSuppressNativeTitles'
import { useTheme } from '@/hooks/useTheme'

const sshStore = useSshStore()
const accessStore = useAccessStore()
const desktopStore = useDesktopStore()
const uploadCenterStore = useUploadCenterStore()
let unsubscribeElectronWindowState: (() => void) | undefined

useSuppressNativeTitles()
const { theme, themeOverrides } = useTheme()

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

onMounted(async () => {
  window.addEventListener('beforeunload', handleBeforeUnload)

  const electronWindow = window.hostDeck?.window
  if (!electronWindow) {
    return
  }

  desktopStore.setElectronWindowState(await electronWindow.getState())
  unsubscribeElectronWindowState = electronWindow.onStateChanged((state) => {
    desktopStore.setElectronWindowState(state)
  })
})

onBeforeUnmount(() => {
  window.removeEventListener('beforeunload', handleBeforeUnload)
  unsubscribeElectronWindowState?.()
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
                <AccessLoginScreen v-if="!accessStore.authenticated" />
                <DesktopShell v-else-if="sshStore.isConnected" />
                <LoginScreen v-else />
              </Transition>
            </div>
          </NMessageProvider>
        </NNotificationProvider>
      </NDialogProvider>
    </NLoadingBarProvider>
  </NConfigProvider>
</template>

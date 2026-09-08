<script setup lang="ts">
import { computed } from 'vue'
import {
  Settings,
  Activity,
  ChartLine,
  Document,
  Image,
  ListBoxes,
  Folder,
  Launch,
  Logout,
  Terminal,
  ApplicationWeb,
  Connect,
  Time,
} from '@vicons/carbon'
import { LogoDocker } from '@vicons/ionicons5'
import { ScrollText } from '@lucide/vue'
import type { Component } from 'vue'
import dashboardIconUrl from '@/assets/mac-tahoe/src/apps/scalable/utilities-system-monitor.svg'
import dockerIconUrl from '@/assets/mac-tahoe/src/apps/scalable/docker.svg'
import editorIconUrl from '@/assets/mac-tahoe/src/apps/scalable/accessories-text-editor.svg'
import fallbackAppIconUrl from '@/assets/mac-tahoe/src/apps/scalable/application-default-icon.svg'
import fileManagerIconUrl from '@/assets/mac-tahoe/src/apps/scalable/file-manager.svg'
import linkIconUrl from '@/assets/mac-tahoe/src/apps/scalable/junction.svg'
import logoutIconUrl from '@/assets/mac-tahoe/src/apps/scalable/log-out.svg'
import mediaIconUrl from '@/assets/mac-tahoe/src/apps/scalable/eog.svg'
import operationLogIconUrl from '@/assets/mac-tahoe/src/apps/scalable/gpk-log.svg'
import portForwardIconUrl from '@/assets/mac-tahoe/src/apps/22/network-connect.svg'
import secureBrowserIconUrl from '@/assets/mac-tahoe/src/apps/scalable/web-browser.svg'
import processIconUrl from '@/assets/mac-tahoe/src/apps/scalable/stacks-task-manager.svg'
import realtimeLogIconUrl from '@/assets/mac-tahoe/src/apps/scalable/logview.svg'
import runtimeIconUrl from '@/assets/mac-tahoe/src/apps/scalable/multitasking-view.svg'
import settingsIconUrl from '@/assets/mac-tahoe/src/apps/scalable/preferences-system.svg'
import taskIconUrl from '@/assets/mac-tahoe/src/apps/scalable/evolution-tasks.svg'
import terminalIconUrl from '@/assets/mac-tahoe/src/apps/scalable/terminal.svg'
import type { AppIconKey } from '@/types/desktop'

const props = withDefaults(
  defineProps<{
    color?: string
    name: AppIconKey
    size?: number
    themed?: boolean
  }>(),
  {
    size: 18,
    themed: false,
  },
)

const iconMap: Record<AppIconKey, Component> = {
  dashboard: ChartLine,
  'cron-task': Time,
  docker: LogoDocker,
  editor: Document,
  folder: Folder,
  'iframe-app': ApplicationWeb,
  link: Launch,
  logout: Logout,
  media: Image,
  opencode: ApplicationWeb,
  'operation-log': ListBoxes,
  'realtime-log': ScrollText,
  process: Activity,
  'port-forward': Connect,
  'secure-browser': ApplicationWeb,
  runtime: ApplicationWeb,
  settings: Settings,
  terminal: Terminal,
}

const icon = computed(() => iconMap[props.name])
const themedIconMap: Record<AppIconKey, string> = {
  dashboard: dashboardIconUrl,
  'cron-task': taskIconUrl,
  docker: dockerIconUrl,
  editor: editorIconUrl,
  folder: fileManagerIconUrl,
  'iframe-app': fallbackAppIconUrl,
  link: linkIconUrl,
  logout: logoutIconUrl,
  media: mediaIconUrl,
  opencode: '/opencode.ico',
  'operation-log': operationLogIconUrl,
  'realtime-log': realtimeLogIconUrl,
  process: processIconUrl,
  'port-forward': portForwardIconUrl,
  'secure-browser': secureBrowserIconUrl,
  runtime: runtimeIconUrl,
  settings: settingsIconUrl,
  terminal: terminalIconUrl,
}
const iconImageSrc = computed(() => {
  if (props.themed) {
    return themedIconMap[props.name]
  }

  return props.name === 'opencode' ? '/opencode.ico' : null
})
</script>

<template>
  <img
    v-if="iconImageSrc"
    :src="iconImageSrc"
    :width="size"
    :height="size"
    alt=""
    aria-hidden="true"
    class="block flex-none object-contain"
    :class="{ 'rounded-[22%]': name === 'opencode', 'scale-[0.92]': name === 'port-forward' }"
    draggable="false"
  />
  <NIcon v-else :color="color" :size="size">
    <component :is="icon" />
  </NIcon>
</template>

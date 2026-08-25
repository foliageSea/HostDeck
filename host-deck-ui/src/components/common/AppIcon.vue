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
import dashboardIconUrl from '@/assets/app-icons/mac-tahoe/utilities-system-monitor.svg'
import dockerIconUrl from '@/assets/app-icons/mac-tahoe/docker.svg'
import editorIconUrl from '@/assets/app-icons/mac-tahoe/accessories-text-editor.svg'
import fallbackAppIconUrl from '@/assets/app-icons/mac-tahoe/application-default-icon.svg'
import fileManagerIconUrl from '@/assets/app-icons/mac-tahoe/file-manager.svg'
import linkIconUrl from '@/assets/app-icons/mac-tahoe/junction.svg'
import logoutIconUrl from '@/assets/app-icons/mac-tahoe/log-out.svg'
import mediaIconUrl from '@/assets/app-icons/mac-tahoe/eog.svg'
import operationLogIconUrl from '@/assets/app-icons/mac-tahoe/gpk-log.svg'
import portForwardIconUrl from '@/assets/app-icons/mac-tahoe/gnome-connections.svg'
import processIconUrl from '@/assets/app-icons/mac-tahoe/stacks-task-manager.svg'
import realtimeLogIconUrl from '@/assets/app-icons/mac-tahoe/logview.svg'
import runtimeIconUrl from '@/assets/app-icons/mac-tahoe/multitasking-view.svg'
import settingsIconUrl from '@/assets/app-icons/mac-tahoe/preferences-system.svg'
import taskIconUrl from '@/assets/app-icons/mac-tahoe/evolution-tasks.svg'
import terminalIconUrl from '@/assets/app-icons/mac-tahoe/terminal.svg'
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
    :class="{ 'rounded-[22%]': name === 'opencode' }"
    draggable="false"
  />
  <NIcon v-else :color="color" :size="size">
    <component :is="icon" />
  </NIcon>
</template>

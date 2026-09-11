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
import { themedAppIconMap } from '@/lib/app-icons'
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
  'task-center': ListBoxes,
}

const icon = computed(() => iconMap[props.name])
const iconImageSrc = computed(() => {
  if (props.themed) {
    return themedAppIconMap[props.name]
  }

  if (props.name === 'opencode') return themedAppIconMap.opencode
  return props.name === 'process' ? themedAppIconMap.process : null
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

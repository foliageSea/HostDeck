<script setup lang="ts">
import { computed } from 'vue'
import { Settings, ChartLine, Document, Image, Folder, Launch, Logout, Terminal, ApplicationWeb } from '@vicons/carbon'
import { LogoDocker } from '@vicons/ionicons5'
import type { Component } from 'vue'
import type { AppIconKey } from '@/types/desktop'

const props = withDefaults(
  defineProps<{
    color?: string
    name: AppIconKey
    size?: number
  }>(),
  {
    size: 18,
  },
)

const iconMap: Record<AppIconKey, Component> = {
  dashboard: ChartLine,
  docker: LogoDocker,
  editor: Document,
  folder: Folder,
  link: Launch,
  logout: Logout,
  media: Image,
  runtime: ApplicationWeb,
  settings: Settings,
  terminal: Terminal,
}

const icon = computed(() => iconMap[props.name])
</script>

<template>
  <NIcon :color="color" :size="size">
    <component :is="icon" />
  </NIcon>
</template>

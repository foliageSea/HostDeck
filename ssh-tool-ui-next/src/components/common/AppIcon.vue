<script setup lang="ts">
import { computed } from 'vue'
import { Settings, ChartLine, Document, Image, Folder, Launch, Logout, Terminal, ApplicationWeb, TreeViewAlt } from '@vicons/carbon'
import { LogoDocker } from '@vicons/ionicons5'
import type { Component } from 'vue'
import type { AppIconKey } from '@/types/desktop'

const props = withDefaults(
  defineProps<{
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
  process: TreeViewAlt,
  runtime: ApplicationWeb,
  settings: Settings,
  terminal: Terminal,
}

const icon = computed(() => iconMap[props.name])
</script>

<template>
  <NIcon :size="size">
    <component :is="icon" />
  </NIcon>
</template>

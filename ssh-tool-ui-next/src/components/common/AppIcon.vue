<script setup lang="ts">
import { computed } from 'vue'
import { Application, ChartLine, Folder, Logout, Terminal } from '@vicons/carbon'
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
  folder: Folder,
  logout: Logout,
  settings: Application,
  terminal: Terminal,
}

const icon = computed(() => iconMap[props.name])
</script>

<template>
  <NIcon :size="size">
    <component :is="icon" />
  </NIcon>
</template>

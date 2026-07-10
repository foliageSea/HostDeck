<script setup lang="ts">
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()
</script>

<template>
  <div class="grid grid-cols-4 gap-[12px] lt-md:grid-cols-2 lt-sm:grid-cols-1">
    <NCard
      size="small"
      :bordered="false"
      class="app-radius-card rounded-[18px]"
      :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.84)]'"
    >
      <div
        class="text-[12px]"
        :class="
          settingsStore.isDark ? 'text-[rgba(226,232,240,0.68)]' : 'text-[rgba(100,116,139,0.92)]'
        "
      >
        运行中容器
      </div>
      <div class="mt-[6px] text-[28px] font-700">{{ controller.runningContainers }}</div>
    </NCard>
    <NCard
      size="small"
      :bordered="false"
      class="app-radius-card rounded-[18px]"
      :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.84)]'"
    >
      <div
        class="text-[12px]"
        :class="
          settingsStore.isDark ? 'text-[rgba(226,232,240,0.68)]' : 'text-[rgba(100,116,139,0.92)]'
        "
      >
        已停止容器
      </div>
      <div class="mt-[6px] text-[28px] font-700">{{ controller.stoppedContainers }}</div>
    </NCard>
    <NCard
      size="small"
      :bordered="false"
      class="app-radius-card rounded-[18px]"
      :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.84)]'"
    >
      <div
        class="text-[12px]"
        :class="
          settingsStore.isDark ? 'text-[rgba(226,232,240,0.68)]' : 'text-[rgba(100,116,139,0.92)]'
        "
      >
        镜像总数
      </div>
      <div class="mt-[6px] text-[28px] font-700">{{ controller.imageSummary.total }}</div>
    </NCard>
    <NCard
      size="small"
      :bordered="false"
      class="app-radius-card rounded-[18px]"
      :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.84)]'"
    >
      <div
        class="text-[12px]"
        :class="
          settingsStore.isDark ? 'text-[rgba(226,232,240,0.68)]' : 'text-[rgba(100,116,139,0.92)]'
        "
      >
        悬空镜像
      </div>
      <div class="mt-[6px] text-[28px] font-700">{{ controller.danglingImages }}</div>
    </NCard>
  </div>
</template>

<script setup lang="ts">
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()
</script>

<template>
  <div class="grid grid-cols-4 gap-[12px] lt-md:grid-cols-2 lt-sm:grid-cols-1">
    <NCard size="small" :bordered="false" class="rounded-[18px] bg-[rgba(15,23,42,0.72)]">
      <div class="text-[12px] text-[rgba(226,232,240,0.68)]">运行中容器</div>
      <div class="mt-[6px] text-[28px] font-700">{{ controller.runningContainers }}</div>
    </NCard>
    <NCard size="small" :bordered="false" class="rounded-[18px] bg-[rgba(15,23,42,0.72)]">
      <div class="text-[12px] text-[rgba(226,232,240,0.68)]">已停止容器</div>
      <div class="mt-[6px] text-[28px] font-700">{{ controller.stoppedContainers }}</div>
    </NCard>
    <NCard size="small" :bordered="false" class="rounded-[18px] bg-[rgba(15,23,42,0.72)]">
      <div class="text-[12px] text-[rgba(226,232,240,0.68)]">镜像总数</div>
      <div class="mt-[6px] text-[28px] font-700">{{ controller.imageSummary.total }}</div>
    </NCard>
    <NCard size="small" :bordered="false" class="rounded-[18px] bg-[rgba(15,23,42,0.72)]">
      <div class="text-[12px] text-[rgba(226,232,240,0.68)]">悬空镜像</div>
      <div class="mt-[6px] text-[28px] font-700">{{ controller.danglingImages }}</div>
    </NCard>
  </div>
</template>

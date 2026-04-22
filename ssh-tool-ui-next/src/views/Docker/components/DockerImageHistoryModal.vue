<script setup lang="ts">
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()
</script>

<template>
  <NModal v-model:show="controller.imageHistoryVisible" preset="card" :title="controller.imageHistoryTitle" style="width: min(960px, 92vw)">
    <NSpin :show="controller.imageHistoryLoading">
      <NDataTable
        :single-line="false"
        :columns="controller.imageHistoryColumns"
        :data="controller.imageHistoryItems"
        :scroll-x="1260"
        size="small"
      />
    </NSpin>
  </NModal>
</template>

<script setup lang="ts">
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()
</script>

<template>
  <NModal v-model:show="controller.imageHistoryVisible" preset="card" :title="controller.imageHistoryTitle" style="width: min(960px, 92vw)">
    <NSpin :show="controller.imageHistoryLoading" class="history-table-shell">
      <NDataTable
        class="history-table"
        :single-line="false"
        :columns="controller.imageHistoryColumns"
        :data="controller.imageHistoryItems"
        :min-height="420"
        :max-height="420"
        :scroll-x="1260"
        flex-height
        size="small"
      />
    </NSpin>
  </NModal>
</template>

<style scoped>
.history-table-shell {
  display: block;
}

.history-table {
  min-width: 100%;
}

.history-table-shell :deep(.n-data-table-base-table-body) {
  scrollbar-width: thin;
  scrollbar-color: rgba(148, 163, 184, 0.34) transparent;
}

.history-table-shell :deep(.n-data-table-base-table-body::-webkit-scrollbar) {
  width: 10px;
  height: 10px;
}

.history-table-shell :deep(.n-data-table-base-table-body::-webkit-scrollbar-track),
.history-table-shell :deep(.n-data-table-base-table-body::-webkit-scrollbar-corner) {
  background: transparent;
}

.history-table-shell :deep(.n-data-table-base-table-body::-webkit-scrollbar-thumb) {
  border: 3px solid transparent;
  border-radius: 999px;
  background-clip: padding-box;
  background-color: rgba(148, 163, 184, 0.34);
}

.history-table-shell:hover :deep(.n-data-table-base-table-body::-webkit-scrollbar-thumb) {
  background-color: rgba(96, 165, 250, 0.52);
}
</style>

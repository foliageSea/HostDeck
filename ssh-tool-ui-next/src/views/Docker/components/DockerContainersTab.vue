<script setup lang="ts">
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()
</script>

<template>
  <div class="flex flex-col">
    <div class="mb-[12px] flex flex-wrap items-start justify-between gap-[12px]">
      <NSpace>
        <NSelect
          :value="controller.containerStatusFilter"
          class="w-[128px]"
          :options="controller.containerStatusOptions"
          size="small"
          @update:value="controller.setContainerStatusFilter"
        />
        <NButton quaternary :loading="controller.batchProcessing" @click="controller.batchStartSelected">批量启动</NButton>
        <NButton quaternary :loading="controller.batchProcessing" @click="controller.batchStopSelected">批量停止</NButton>
        <NButton quaternary @click="controller.confirmRemoveStoppedContainers">清理已停止</NButton>
        <NButton quaternary @click="controller.confirmPruneImages(false)">清理悬空镜像</NButton>
        <NButton quaternary @click="controller.confirmPruneImages(true)">清理无引用镜像</NButton>
        <div class="mt-1 flex gap-1">
          <NTag round size="small">已选 {{ controller.selectedContainerIds.length }}</NTag>
          <NTag round size="small">显示 {{ controller.containerTotal }} / {{ controller.containerSummary.total }}</NTag>
        </div>
      </NSpace>
    </div>

    <div class="docker-table-shell">
      <NDataTable
        :checked-row-keys="controller.selectedContainerIds"
        class="docker-table"
        :single-line="false"
        :columns="controller.containerColumns"
        :data="controller.containers"
        :pagination="controller.containerPagination"
        :row-key="controller.containerRowKey"
        remote
        size="small"
        @update:checked-row-keys="controller.updateSelectedContainerIds"
        @update:page="controller.handleContainerPageChange"
        @update:page-size="controller.handleContainerPageSizeChange"
      />
    </div>
  </div>
</template>

<style scoped>
.docker-table-shell {
  flex: none;
  overflow: visible;
}

.docker-table {
  min-width: 100%;
}

.docker-table-shell :deep(.n-data-table-base-table-body) {
  scrollbar-width: thin;
  scrollbar-color: rgba(148, 163, 184, 0.34) transparent;
}

.docker-table-shell :deep(.n-data-table-base-table-body::-webkit-scrollbar) {
  width: 10px;
  height: 10px;
}

.docker-table-shell :deep(.n-data-table-base-table-body::-webkit-scrollbar-track),
.docker-table-shell :deep(.n-data-table-base-table-body::-webkit-scrollbar-corner) {
  background: transparent;
}

.docker-table-shell :deep(.n-data-table-base-table-body::-webkit-scrollbar-thumb) {
  border: 3px solid transparent;
  border-radius: 999px;
  background-clip: padding-box;
  background-color: rgba(148, 163, 184, 0.34);
}

.docker-table-shell:hover :deep(.n-data-table-base-table-body::-webkit-scrollbar-thumb) {
  background-color: rgba(96, 165, 250, 0.52);
}

.docker-table-shell :deep(.container-port-summary) {
  display: inline-block;
  max-width: 130px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  vertical-align: middle;
}

.docker-table-shell :deep(.container-port-popover) {
  display: flex;
  flex-direction: column;
  gap: 6px;
  max-width: 360px;
}

.docker-table-shell :deep(.container-port-item) {
  font-family: Consolas, 'Cascadia Mono', 'Courier New', monospace;
  font-size: 12px;
  line-height: 1.5;
  word-break: break-all;
}

.docker-table-shell :deep(.container-action-popover) {
  max-width: 260px;
}
</style>

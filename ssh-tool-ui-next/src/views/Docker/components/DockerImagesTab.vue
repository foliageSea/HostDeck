<script setup lang="ts">
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()
</script>

<template>
  <div class="flex flex-col">
    <div class="mb-[12px] text-[13px] text-[rgba(226,232,240,0.68)]">支持镜像重新打标签、查看构建历史和引用容器。</div>
    <div class="docker-table-shell">
      <NDataTable
        class="docker-table"
        :single-line="false"
        :columns="controller.imageColumns"
        :data="controller.images"
        :pagination="controller.imagePagination"
        remote
        size="small"
        @update:page="controller.handleImagePageChange"
        @update:page-size="controller.handleImagePageSizeChange"
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

.docker-table-shell :deep(.container-action-popover) {
  max-width: 260px;
}
</style>

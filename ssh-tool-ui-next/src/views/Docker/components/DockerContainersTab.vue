<script setup lang="ts">
import { Grid, List } from '@vicons/carbon'
import type { DockerContainer } from '@/api/docker'
import type { DockerViewController } from '../hooks/useDockerView'

const props = defineProps<{
  controller: DockerViewController
}>()

function isContainerSelected(id: string) {
  return props.controller.selectedContainerIds.includes(id)
}

function toggleContainerSelection(id: string, checked: boolean) {
  const selectedIds = checked
    ? Array.from(new Set([...props.controller.selectedContainerIds, id]))
    : props.controller.selectedContainerIds.filter((item) => item !== id)

  props.controller.updateSelectedContainerIds(selectedIds)
}

function getContainerStatusType(container: DockerContainer) {
  if (container.state === 'running') {
    return 'success'
  }

  if (container.status.toLowerCase().includes('paused')) {
    return 'warning'
  }

  return 'default'
}

function getContainerResource(container: DockerContainer) {
  const stats = props.controller.statsMap[container.id]
  const diagnostics = props.controller.diagnosticsMap[container.id]

  if (!stats) {
    return '-'
  }

  return `${stats.cpuPercent} CPU / ${stats.memUsage}${diagnostics ? ` / 重启 ${diagnostics.restartCount}` : ''}`
}

function getPortsTitle(container: DockerContainer) {
  return container.ports.length ? container.ports.join('\n') : '无端口映射'
}

function isPaused(container: DockerContainer) {
  return container.status.toLowerCase().includes('paused')
}
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

      <NButtonGroup size="small">
        <NButton
          :type="controller.containerViewMode === 'card' ? 'primary' : 'default'"
          title="卡片视图"
          aria-label="卡片视图"
          @click="controller.setContainerViewMode('card')"
        >
          <template #icon>
            <NIcon><Grid /></NIcon>
          </template>
        </NButton>
        <NButton
          :type="controller.containerViewMode === 'table' ? 'primary' : 'default'"
          title="表格视图"
          aria-label="表格视图"
          @click="controller.setContainerViewMode('table')"
        >
          <template #icon>
            <NIcon><List /></NIcon>
          </template>
        </NButton>
      </NButtonGroup>
    </div>

    <div v-if="controller.containerViewMode === 'card'" class="docker-card-shell">
      <NEmpty v-if="controller.containers.length === 0" description="暂无容器" />

      <div v-else class="docker-card-grid">
        <NCard
          v-for="container in controller.containers"
          :key="container.id"
          class="docker-card"
          content-class="docker-card-content"
          size="small"
          :bordered="false"
        >
          <template #header>
            <div class="min-w-0 flex items-start gap-[10px]">
              <NCheckbox
                :checked="isContainerSelected(container.id)"
                class="mt-[2px]"
                @update:checked="toggleContainerSelection(container.id, $event)"
              />
              <div class="min-w-0 flex-1">
                <div class="truncate text-[15px] font-600" :title="container.name">{{ container.name }}</div>
                <div class="mt-[4px] truncate text-[12px] text-[rgba(226,232,240,0.58)]" :title="container.id">
                  {{ container.id.slice(0, 12) }}
                </div>
              </div>
            </div>
          </template>

          <template #header-extra>
            <NTag round size="small" :type="getContainerStatusType(container)">{{ container.status }}</NTag>
          </template>

          <div class="docker-card-fields">
            <div class="docker-card-field wide">
              <span>镜像</span>
              <strong :title="container.image">{{ container.image }}</strong>
            </div>
            <div class="docker-card-field">
              <span>资源</span>
              <strong>{{ getContainerResource(container) }}</strong>
            </div>
            <div class="docker-card-field">
              <span>创建时间</span>
              <strong>{{ controller.formatTime(container.createdAt) }}</strong>
            </div>
            <div class="docker-card-field wide">
              <span>端口</span>
              <strong :title="getPortsTitle(container)">
                <template v-if="container.ports.length">{{ container.ports.slice(0, 2).join(', ') }}</template>
                <template v-else>-</template>
                <span v-if="container.ports.length > 2"> 等 {{ container.ports.length }} 项</span>
              </strong>
            </div>
          </div>

          <template #footer>
            <div class="docker-card-actions">
              <NButton
                v-if="container.state === 'running'"
                size="tiny"
                quaternary
                @click="controller.confirmContainerAction(container, 'stop')"
              >
                停止
              </NButton>
              <NButton v-else size="tiny" quaternary @click="controller.confirmContainerAction(container, 'start')">启动</NButton>
              <NButton size="tiny" quaternary @click="controller.confirmContainerAction(container, 'restart')">重启</NButton>
              <NButton
                size="tiny"
                quaternary
                :disabled="container.state !== 'running'"
                @click="controller.handleContainerAdvancedAction(container, isPaused(container) ? 'unpause' : 'pause')"
              >
                {{ isPaused(container) ? '恢复' : '暂停' }}
              </NButton>
              <NButton size="tiny" quaternary @click="controller.viewLogs(container)">日志</NButton>
              <NButton size="tiny" quaternary @click="controller.viewInspect(container)">Inspect</NButton>
              <NButton size="tiny" quaternary @click="controller.openRenameDialog(container)">重命名</NButton>
              <NButton size="tiny" quaternary @click="controller.recreateContainer(container)">重建</NButton>
              <NButton
                size="tiny"
                quaternary
                :disabled="container.state !== 'running'"
                @click="controller.enterShell(container)"
              >
                Shell
              </NButton>
              <NButton size="tiny" quaternary type="error" @click="controller.confirmContainerAction(container, 'remove')">
                删除
              </NButton>
            </div>
          </template>
        </NCard>
      </div>

      <div v-if="controller.containerTotal > 0" class="docker-card-pagination">
        <NPagination
          :page="controller.containerPagination.page"
          :page-size="controller.containerPagination.pageSize"
          :item-count="controller.containerPagination.itemCount"
          :page-sizes="controller.containerPagination.pageSizes"
          show-size-picker
          @update:page="controller.handleContainerPageChange"
          @update:page-size="controller.handleContainerPageSizeChange"
        />
      </div>
    </div>

    <div v-else class="docker-table-shell">
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
.docker-card-shell,
.docker-table-shell {
  flex: none;
  overflow: visible;
}

.docker-card-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(310px, 1fr));
  gap: 12px;
}

.docker-card {
  border: 1px solid rgba(148, 163, 184, 0.16);
  background: linear-gradient(145deg, rgba(15, 23, 42, 0.72), rgba(30, 41, 59, 0.46));
  box-shadow: 0 18px 42px rgba(2, 6, 23, 0.18);
}

.docker-card:hover {
  border-color: rgba(96, 165, 250, 0.36);
  background: linear-gradient(145deg, rgba(15, 23, 42, 0.84), rgba(30, 64, 175, 0.32));
}

.docker-card :deep(.docker-card-content) {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.docker-card-fields {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
}

.docker-card-field {
  min-width: 0;
  border-radius: 12px;
  background: rgba(15, 23, 42, 0.38);
  padding: 9px 10px;
}

.docker-card-field.wide {
  grid-column: 1 / -1;
}

.docker-card-field span {
  display: block;
  margin-bottom: 4px;
  color: rgba(226, 232, 240, 0.52);
  font-size: 12px;
}

.docker-card-field strong {
  display: block;
  overflow: hidden;
  color: rgba(248, 250, 252, 0.9);
  font-size: 13px;
  font-weight: 500;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.docker-card-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.docker-card-pagination {
  display: flex;
  justify-content: flex-end;
  margin-top: 14px;
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

@media (max-width: 640px) {
  .docker-card-grid {
    grid-template-columns: 1fr;
  }

  .docker-card-fields {
    grid-template-columns: 1fr;
  }
}
</style>

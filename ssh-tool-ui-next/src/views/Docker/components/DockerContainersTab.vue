<script setup lang="ts">
import { Add, Pin, PinFilled } from '@vicons/carbon'
import type { DockerContainer } from '@/api/docker'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'

const props = defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()

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
  if (!props.controller.containerResourceLoadedMap[container.id]) {
    return ''
  }

  const stats = props.controller.statsMap[container.id]
  const diagnostics = props.controller.diagnosticsMap[container.id]

  if (!stats) {
    return '暂无数据'
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
  <div class="flex h-full min-h-0 flex-col overflow-hidden"
    :class="settingsStore.isDark ? 'docker-theme-dark' : 'docker-theme-light'">
    <div class="mb-[12px] flex flex-wrap items-start justify-between gap-[12px]">
      <NSpace>
        <NSelect :value="controller.containerStatusFilter" class="w-[128px]"
          :options="controller.containerStatusOptions" size="small"
          @update:value="controller.setContainerStatusFilter" />
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

      <NButton quaternary @click="controller.openCreateContainer">
        <template #icon>
          <NIcon>
            <Add />
          </NIcon>
        </template>
        新建容器
      </NButton>
    </div>

    <div class="docker-card-shell">
      <NEmpty v-if="controller.containers.length === 0" description="暂无容器" />

      <div v-else class="docker-card-list">
        <NCard v-for="container in controller.containers" :key="container.id" class="docker-card"
          content-class="docker-card-content" size="small" :bordered="false">
          <template #header>
            <div class="min-w-0 flex items-start gap-[10px]">
              <NCheckbox :checked="isContainerSelected(container.id)" class="mt-[2px]"
                @update:checked="toggleContainerSelection(container.id, $event)" />
              <div class="min-w-0 flex-1">
                <div class="truncate text-[15px] font-600" :title="container.name">{{ container.name }}</div>
                <div class="mt-[4px] truncate text-[12px]"
                  :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.58)]' : 'text-[rgba(100,116,139,0.88)]'"
                  :title="container.id">
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
              <strong v-if="controller.containerResourceLoadedMap[container.id]">{{ getContainerResource(container)
                }}</strong>
              <NButton v-else text type="primary" :loading="controller.containerResourceLoadingMap[container.id]"
                @click="controller.refreshContainerResource(container.id)">
                获取资源
              </NButton>
            </div>
            <div class="docker-card-field">
              <span>创建时间</span>
              <strong>{{ controller.formatTime(container.createdAt) }}</strong>
            </div>
            <div class="docker-card-field wide">
              <span>端口</span>
              <div class="docker-card-port-list" :title="getPortsTitle(container)">
                <template v-if="container.ports.length">
                  <span v-for="port in container.ports.slice(0, 3)" :key="port" class="docker-card-port-item">
                    <NButton text type="primary" size="tiny" :disabled="!controller.getContainerPortUrl(port)"
                      :title="controller.getContainerPortUrl(port) ? `打开 ${controller.getContainerPortUrl(port)}` : `${port} 未映射宿主机端口`"
                      @click.stop="controller.openContainerPort(port)">
                      {{ port }}
                    </NButton>
                    <NButton text size="tiny" :disabled="!controller.getContainerPortUrl(port)"
                      :aria-label="controller.isContainerPortPinned(port) ? '从桌面移除端口链接' : '添加端口链接到桌面'"
                      :title="controller.isContainerPortPinned(port) ? '从桌面移除端口链接' : '添加端口链接到桌面'"
                      :type="controller.isContainerPortPinned(port) ? 'success' : 'default'"
                      @click.stop="controller.toggleContainerPortDesktopPin(container, port)">
                      <template #icon>
                        <NIcon>
                          <component :is="controller.isContainerPortPinned(port) ? PinFilled : Pin" />
                        </NIcon>
                      </template>
                    </NButton>
                  </span>
                </template>
                <template v-else>-</template>
                <span v-if="container.ports.length > 3">等 {{ container.ports.length }} 项</span>
              </div>
            </div>
          </div>

          <template #footer>
            <div class="docker-card-actions">
              <NButton v-if="container.state === 'running'" size="tiny" quaternary
                @click="controller.confirmContainerAction(container, 'stop')">
                停止
              </NButton>
              <NButton v-else size="tiny" quaternary @click="controller.confirmContainerAction(container, 'start')">启动
              </NButton>
              <NButton size="tiny" quaternary @click="controller.confirmContainerAction(container, 'restart')">重启
              </NButton>
              <NButton size="tiny" quaternary :disabled="container.state !== 'running'"
                @click="controller.handleContainerAdvancedAction(container, isPaused(container) ? 'unpause' : 'pause')">
                {{ isPaused(container) ? '恢复' : '暂停' }}
              </NButton>
              <NButton size="tiny" quaternary @click="controller.viewLogs(container)">日志</NButton>
              <NButton size="tiny" quaternary @click="controller.viewInspect(container)">Inspect</NButton>
              <NButton size="tiny" quaternary @click="controller.openRenameDialog(container)">重命名</NButton>
              <NButton size="tiny" quaternary @click="controller.recreateContainer(container)">重建</NButton>
              <NButton size="tiny" quaternary :disabled="container.state !== 'running'"
                @click="controller.enterShell(container)">
                Shell
              </NButton>
              <NButton size="tiny" quaternary type="error"
                @click="controller.confirmContainerAction(container, 'remove')">
                删除
              </NButton>
            </div>
          </template>
        </NCard>
      </div>

      <div v-if="controller.containerTotal > 0" class="docker-card-pagination">
        <NPagination :page="controller.containerPagination.page" :page-size="controller.containerPagination.pageSize"
          :item-count="controller.containerPagination.itemCount" :page-sizes="controller.containerPagination.pageSizes"
          show-size-picker @update:page="controller.handleContainerPageChange"
          @update:page-size="controller.handleContainerPageSizeChange" />
      </div>
    </div>
  </div>
</template>

<style scoped>
.docker-theme-dark {
  --docker-card-border: rgba(148, 163, 184, 0.16);
  --docker-card-bg: linear-gradient(145deg, rgba(15, 23, 42, 0.72), rgba(30, 41, 59, 0.46));
  --docker-card-shadow: 0 18px 42px rgba(2, 6, 23, 0.18);
  --docker-card-border-hover: rgba(var(--app-primary-rgb), 0.42);
  --docker-card-bg-hover: linear-gradient(145deg, rgba(15, 23, 42, 0.84), rgba(var(--app-primary-rgb), 0.28));
  --docker-card-field-bg: rgba(15, 23, 42, 0.38);
  --docker-card-label-color: rgba(226, 232, 240, 0.52);
  --docker-card-value-color: rgba(248, 250, 252, 0.9);
  --docker-pager-bg: rgba(15, 23, 42, 0.9);
  --docker-pager-border: rgba(148, 163, 184, 0.14);
}

.docker-theme-light {
  --docker-card-border: rgba(148, 163, 184, 0.22);
  --docker-card-bg: linear-gradient(145deg, rgba(255, 255, 255, 0.96), rgba(241, 245, 249, 0.92));
  --docker-card-shadow: 0 18px 40px rgba(15, 23, 42, 0.08);
  --docker-card-border-hover: rgba(var(--app-primary-rgb), 0.34);
  --docker-card-bg-hover: linear-gradient(145deg, rgba(255, 255, 255, 0.98), rgba(var(--app-primary-rgb), 0.14));
  --docker-card-field-bg: rgba(241, 245, 249, 0.92);
  --docker-card-label-color: rgba(100, 116, 139, 0.9);
  --docker-card-value-color: rgba(30, 41, 59, 0.92);
  --docker-pager-bg: rgba(255, 255, 255, 0.94);
  --docker-pager-border: rgba(148, 163, 184, 0.18);
}

.docker-card-shell {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 14px;
  min-height: 0;
  overflow: hidden;
}

.docker-card-list {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 12px;
  min-height: 0;
  overflow: auto;
  padding-right: 4px;
}

.docker-card {
  width: 100%;
  border: 1px solid var(--docker-card-border);
  background: var(--docker-card-bg);
  box-shadow: var(--docker-card-shadow);
}

.docker-card:hover {
  border-color: var(--docker-card-border-hover);
  background: var(--docker-card-bg-hover);
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
  background: var(--docker-card-field-bg);
  padding: 9px 10px;
}

.docker-card-field.wide {
  grid-column: 1 / -1;
}

.docker-card-field span {
  display: block;
  margin-bottom: 4px;
  color: var(--docker-card-label-color);
  font-size: 12px;
}

.docker-card-field strong {
  display: block;
  overflow: hidden;
  color: var(--docker-card-value-color);
  font-size: 13px;
  font-weight: 500;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.docker-card-port-list {
  display: flex;
  min-width: 0;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  color: var(--docker-card-value-color);
  font-size: 13px;
  font-weight: 500;
}

.docker-card-port-item {
  display: inline-flex;
  min-width: 0;
  align-items: center;
  gap: 4px;
}

.docker-card-port-list :deep(.n-button__content) {
  display: block;
  max-width: 180px;
  overflow: hidden;
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
  flex: none;
  position: sticky;
  bottom: 0;
  z-index: 1;
  margin-top: auto;
  border-top: 1px solid var(--docker-pager-border);
  background: var(--docker-pager-bg);
  padding-top: 10px;
  backdrop-filter: blur(10px);
  padding: 8px;
}

@media (max-width: 640px) {
  .docker-card-fields {
    grid-template-columns: 1fr;
  }
}
</style>

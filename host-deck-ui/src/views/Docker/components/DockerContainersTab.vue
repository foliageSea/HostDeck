<script setup lang="ts">
import { computed } from 'vue'
import { Add, Pin, PinFilled } from '@vicons/carbon'
import type { DockerContainer } from '@/api/docker'
import CopyableText from '@/components/common/CopyableText.vue'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'
import DockerTabToolbar from './DockerTabToolbar.vue'

const props = defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()
const containerMoreActionOptions = computed(() => [
  { key: 'batch-start', label: '批量启动' },
  { key: 'batch-stop', label: '批量停止' },
  { key: 'divider', type: 'divider' },
  { key: 'cleanup-stopped', label: '清理已停止' },
])

function getContainerRowMoreActionOptions(container: DockerContainer) {
  const paused = isPaused(container)
  const isRunning = container.state === 'running'

  return [
    { key: 'logs', label: '日志' },
    { key: 'shell', label: 'Shell', disabled: !isRunning },
    { key: 'divider-1', type: 'divider' },
    { key: 'pause-toggle', label: paused ? '恢复' : '暂停', disabled: !isRunning },
    { key: 'inspect', label: 'Inspect' },
    { key: 'rename', label: '重命名' },
    { key: 'recreate', label: '重建' },
    { key: 'divider-2', type: 'divider' },
    { key: 'remove', label: '删除' },
  ]
}

function handleContainerMoreAction(key: string) {
  switch (key) {
    case 'batch-start':
      props.controller.batchStartSelected()
      break
    case 'batch-stop':
      props.controller.batchStopSelected()
      break
    case 'cleanup-stopped':
      props.controller.confirmRemoveStoppedContainers()
      break
  }
}

function handleContainerRowMoreAction(container: DockerContainer, key: string) {
  switch (key) {
    case 'logs':
      props.controller.viewLogs(container)
      break
    case 'shell':
      props.controller.enterShell(container)
      break
    case 'pause-toggle':
      props.controller.handleContainerAdvancedAction(
        container,
        isPaused(container) ? 'unpause' : 'pause',
      )
      break
    case 'inspect':
      props.controller.viewInspect(container)
      break
    case 'rename':
      props.controller.openRenameDialog(container)
      break
    case 'recreate':
      props.controller.recreateContainer(container)
      break
    case 'remove':
      props.controller.confirmContainerAction(container, 'remove')
      break
  }
}

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

function getContainerNetworksTitle(container: DockerContainer) {
  return container.networks.length
    ? container.networks
        .map((item) => `${item.name}${item.ipAddress ? ` (${item.ipAddress})` : ''}`)
        .join('\n')
    : '无网络信息'
}

function getContainerNetworkIpsTitle(container: DockerContainer) {
  const ipItems = container.networks
    .filter((item) => item.ipAddress)
    .map((item) => `${item.name}: ${item.ipAddress}`)

  return ipItems.length ? ipItems.join('\n') : '无 IP 地址'
}

function isPaused(container: DockerContainer) {
  return container.status.toLowerCase().includes('paused')
}
</script>

<template>
  <div
    class="flex h-full min-h-0 flex-col overflow-hidden"
    :class="settingsStore.isDark ? 'docker-theme-dark' : 'docker-theme-light'"
  >
    <DockerTabToolbar>
      <template #left>
        <div class="flex gap-1 items-center">
          <NInput
            :value="controller.containerSearchKeyword"
            clearable
            class="w-[min(220px,60vw)] lt-sm:w-full"
            placeholder="搜索容器"
            @update:value="controller.setContainerSearchKeyword"
          />
          <NSelect
            :value="controller.containerStatusFilter"
            class="w-[128px]"
            :options="controller.containerStatusOptions"
            @update:value="controller.setContainerStatusFilter"
          />
          <NDropdown
            trigger="click"
            :options="containerMoreActionOptions"
            @select="handleContainerMoreAction"
          >
            <NButton quaternary :loading="controller.batchProcessing">操作</NButton>
          </NDropdown>
        </div>
      </template>

      <template #actions>
        <NButton type="primary" @click="controller.openCreateContainer">
          <template #icon>
            <NIcon>
              <Add />
            </NIcon>
          </template>
          新建容器
        </NButton>
        <NButton quaternary :loading="controller.loading" @click="controller.refreshContainers"
          >刷新</NButton
        >
      </template>

      <template #meta>
        <NTag round size="small">已选 {{ controller.selectedContainerIds.length }}</NTag>
        <NTag round size="small"
          >显示 {{ controller.containerTotal }} / {{ controller.containerSummary.total }}</NTag
        >
      </template>
    </DockerTabToolbar>

    <div class="docker-card-shell">
      <NEmpty v-if="controller.containers.length === 0" />

      <div v-else class="docker-card-list app-scrollbar app-scrollbar-compact">
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
                <div class="truncate text-[15px] font-600" :title="container.name">
                  {{ container.name }}
                </div>
                <div
                  class="mt-[4px] min-w-0 text-[12px]"
                  :class="
                    settingsStore.isDark
                      ? 'text-[rgba(226,232,240,0.58)]'
                      : 'text-[rgba(100,116,139,0.88)]'
                  "
                  :title="container.id"
                >
                  <CopyableText
                    :text="container.id"
                    :display-text="container.id.slice(0, 12)"
                    success-message="已复制容器 ID。"
                    error-message="复制容器 ID 失败。"
                  />
                </div>
              </div>
            </div>
          </template>

          <template #header-extra>
            <NTag round size="small" :type="getContainerStatusType(container)">{{
              container.status
            }}</NTag>
          </template>

          <div class="docker-card-fields">
            <div class="docker-card-field wide">
              <span>镜像</span>
              <strong :title="container.image">{{ container.image }}</strong>
            </div>
            <div class="docker-card-field">
              <span>资源</span>
              <strong v-if="controller.containerResourceLoadedMap[container.id]">{{
                getContainerResource(container)
              }}</strong>
              <NButton
                v-else
                text
                type="primary"
                :loading="controller.containerResourceLoadingMap[container.id]"
                @click="controller.refreshContainerResource(container.id)"
              >
                获取资源
              </NButton>
            </div>
            <div class="docker-card-field">
              <span>创建时间</span>
              <strong>{{ controller.formatTime(container.createdAt) }}</strong>
            </div>
            <div class="docker-card-field wide">
              <span>网络</span>
              <div class="docker-card-chip-list" :title="getContainerNetworksTitle(container)">
                <template v-if="container.networks.length">
                  <NTag
                    v-for="network in container.networks.slice(0, 3)"
                    :key="network.name"
                    size="small"
                    round
                  >
                    {{ network.name }}
                  </NTag>
                  <span v-if="container.networks.length > 3"
                    >等 {{ container.networks.length }} 项</span
                  >
                </template>
                <template v-else>-</template>
              </div>
            </div>
            <div class="docker-card-field wide">
              <span>IP</span>
              <div class="docker-card-chip-list" :title="getContainerNetworkIpsTitle(container)">
                <template v-if="container.networks.some((item) => item.ipAddress)">
                  <NTag
                    v-for="network in container.networks
                      .filter((item) => item.ipAddress)
                      .slice(0, 3)"
                    :key="`${network.name}-${network.ipAddress}`"
                    size="small"
                    round
                    type="info"
                  >
                    {{ network.ipAddress }}
                  </NTag>
                  <span v-if="container.networks.filter((item) => item.ipAddress).length > 3">
                    等 {{ container.networks.filter((item) => item.ipAddress).length }} 项
                  </span>
                </template>
                <template v-else>-</template>
              </div>
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
              <NButton
                v-else
                size="tiny"
                quaternary
                @click="controller.confirmContainerAction(container, 'start')"
                >启动
              </NButton>
              <NButton
                size="tiny"
                quaternary
                @click="controller.confirmContainerAction(container, 'restart')"
                >重启
              </NButton>
              <NPopover v-if="container.ports.length" trigger="hover" placement="top-end">
                <template #trigger>
                  <NButton quaternary size="tiny" :title="getPortsTitle(container)">
                    端口 {{ container.ports.length }}
                  </NButton>
                </template>

                <div class="docker-port-popover">
                  <div v-for="port in container.ports" :key="port" class="docker-port-popover-item">
                    <NButton
                      text
                      type="primary"
                      size="tiny"
                      :disabled="!controller.getContainerPortUrl(port)"
                      :title="
                        controller.getContainerPortUrl(port)
                          ? `打开 ${controller.getContainerPortUrl(port)}`
                          : `${port} 未映射宿主机端口`
                      "
                      @click.stop="controller.openContainerPort(port)"
                    >
                      {{ port }}
                    </NButton>
                    <NButton
                      text
                      size="tiny"
                      :disabled="!controller.getContainerPortUrl(port)"
                      :aria-label="
                        controller.isContainerPortPinned(port)
                          ? '从桌面移除端口链接'
                          : '添加端口链接到桌面'
                      "
                      :title="
                        controller.isContainerPortPinned(port)
                          ? '从桌面移除端口链接'
                          : '添加端口链接到桌面'
                      "
                      :type="controller.isContainerPortPinned(port) ? 'success' : 'default'"
                      @click.stop="controller.toggleContainerPortDesktopPin(container, port)"
                    >
                      <template #icon>
                        <NIcon>
                          <component :is="controller.isContainerPortPinned(port) ? PinFilled : Pin" />
                        </NIcon>
                      </template>
                    </NButton>
                  </div>
                </div>
              </NPopover>
              <NDropdown
                trigger="click"
                :options="getContainerRowMoreActionOptions(container)"
                @select="(key: string | number) => handleContainerRowMoreAction(container, String(key))"
              >
                <NButton size="tiny" quaternary>更多</NButton>
              </NDropdown>
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
  </div>
</template>

<style scoped>
.docker-theme-dark {
  --docker-card-border: rgba(148, 163, 184, 0.16);
  --docker-card-bg: transparent;
  --docker-card-shadow: none;
  --docker-card-border-hover: rgba(var(--app-primary-rgb), 0.42);
  --docker-card-bg-hover: transparent;
  --docker-card-field-bg: rgba(15, 23, 42, 0.38);
  --docker-card-label-color: rgba(226, 232, 240, 0.52);
  --docker-card-value-color: rgba(248, 250, 252, 0.9);
  --docker-pager-bg: rgba(15, 23, 42, 0.9);
  --docker-pager-border: rgba(148, 163, 184, 0.14);
}

.docker-theme-light {
  --docker-card-border: rgba(148, 163, 184, 0.22);
  --docker-card-bg: transparent;
  --docker-card-shadow: none;
  --docker-card-border-hover: rgba(var(--app-primary-rgb), 0.34);
  --docker-card-bg-hover: transparent;
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
  gap: 8px;
  min-height: 0;
  overflow: auto;
  padding-right: 4px;
}

.docker-card {
  flex: none;
  width: 100%;
  border: 1px solid var(--docker-card-border);
  border-radius: var(--app-radius-card);
  background: var(--docker-card-bg);
  box-shadow: var(--docker-card-shadow);
  overflow: hidden;
}

.docker-card:hover {
  border-color: var(--docker-card-border-hover);
  background: var(--docker-card-bg-hover);
}

.docker-card :deep(.docker-card-content) {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.docker-card :deep(.n-card-header) {
  padding: 10px 12px 8px;
}

.docker-card :deep(.n-card__content) {
  padding: 0 12px 8px;
}

.docker-card :deep(.n-card__footer) {
  padding: 6px 12px 10px;
  background: transparent;
}

.docker-card-fields {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 7px;
}

.docker-card-field {
  min-width: 0;
  border-radius: var(--app-radius-item);
  background: var(--docker-card-field-bg);
  padding: 6px 8px;
}

.docker-card-field.wide {
  grid-column: auto;
}

.docker-card-field span {
  display: block;
  margin-bottom: 2px;
  color: var(--docker-card-label-color);
  font-size: 11px;
}

.docker-card-field strong {
  display: block;
  overflow: hidden;
  color: var(--docker-card-value-color);
  font-size: 12px;
  font-weight: 500;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.docker-card-port-list {
  display: flex;
  min-width: 0;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px;
  color: var(--docker-card-value-color);
  font-size: 12px;
  font-weight: 500;
}

.docker-card-chip-list {
  display: flex;
  min-width: 0;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px;
  overflow: hidden;
  color: var(--docker-card-value-color);
  font-size: 12px;
  font-weight: 500;
}

.docker-card-chip-list :deep(.n-tag) {
  max-width: 100%;
  min-width: 0;
}

.docker-card-chip-list :deep(.n-tag__content) {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.docker-card-port-item {
  display: inline-flex;
  min-width: 0;
  align-items: center;
  gap: 4px;
}

.docker-card-port-list :deep(.n-button__content) {
  display: block;
  max-width: 150px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.docker-card-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  justify-content: flex-end;
}

.docker-port-popover {
  display: flex;
  max-width: min(520px, calc(100vw - 48px));
  flex-direction: column;
  gap: 6px;
}

.docker-port-popover-item {
  display: flex;
  min-width: 0;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.docker-port-popover-item :deep(.n-button:first-child .n-button__content) {
  display: block;
  max-width: 420px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
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
  background: transparent;
  padding-top: 10px;
  backdrop-filter: none;
  padding: 8px;
}

@media (max-width: 640px) {
  .docker-card-fields {
    grid-template-columns: 1fr;
  }
}
</style>

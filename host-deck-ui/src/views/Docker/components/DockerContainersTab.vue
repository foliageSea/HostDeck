<script setup lang="ts">
import { computed, ref } from 'vue'
import { Add } from '@vicons/carbon'
import { Box, ChevronDown, Ellipsis, LogIn, RefreshCw, Search } from '@lucide/vue'
import type { DockerContainer } from '@/api/docker'
import CopyableText from '@/components/common/CopyableText.vue'
import type { DockerViewController } from '../hooks/useDockerView'
import { getContainerStatusPresentation } from '../hooks/dockerViewHelpers'
import DockerTabToolbar from './DockerTabToolbar.vue'

const props = defineProps<{
  controller: DockerViewController
}>()

const selectedPortContainer = ref<DockerContainer | null>(null)
const selectedPort = ref('')
const portActionVisible = ref(false)
const selectedPortUrl = computed(() => props.controller.getContainerPortUrl(selectedPort.value))
const selectedPortPinned = computed(() =>
  props.controller.isContainerPortPinned(selectedPort.value),
)

function getContainerRowMoreActionOptions(container: DockerContainer) {
  const paused = isPaused(container)
  const isRunning = container.state === 'running'

  return [
    { key: 'stats', label: '监控', disabled: !isRunning },
    { key: 'logs', label: '日志' },
    { key: 'shell', label: '终端', disabled: !isRunning },
    { key: 'divider-1', type: 'divider' },
    { key: 'restart', label: '重启', disabled: !isRunning },
    { key: 'pause-toggle', label: paused ? '恢复' : '暂停', disabled: !isRunning },
    { key: 'inspect', label: '检查' },
    { key: 'edit', label: '编辑', disabled: isRunning },
    { key: 'rename', label: '重命名' },
    { key: 'recreate', label: '重建' },
    { key: 'divider-2', type: 'divider' },
    { key: 'remove', label: '删除' },
  ]
}

function getContainerPortOptions(container: DockerContainer) {
  return container.ports.map((port) => ({ key: `port:${port}`, label: port }))
}

function handleContainerRowMoreAction(container: DockerContainer, key: string) {
  if (key.startsWith('port:')) {
    selectedPortContainer.value = container
    selectedPort.value = key.slice('port:'.length)
    portActionVisible.value = true
    return
  }

  switch (key) {
    case 'stats':
      props.controller.viewStats(container)
      break
    case 'logs':
      props.controller.viewLogs(container)
      break
    case 'shell':
      props.controller.enterShell(container)
      break
    case 'restart':
      props.controller.confirmContainerAction(container, 'restart')
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
    case 'edit':
      props.controller.openEditContainer(container)
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

function toggleContainerState(container: DockerContainer) {
  props.controller.confirmContainerAction(
    container,
    container.state === 'running' ? 'stop' : 'start',
  )
}

function openSelectedPort() {
  props.controller.openContainerPort(selectedPort.value)
  portActionVisible.value = false
}

function toggleSelectedPortPin() {
  if (!selectedPortContainer.value) {
    return
  }

  props.controller.toggleContainerPortDesktopPin(selectedPortContainer.value, selectedPort.value)
  portActionVisible.value = false
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
  <div class="flex h-full min-h-0 flex-col overflow-hidden">
    <DockerTabToolbar>
      <template #left>
        <NButton type="primary" @click="controller.openCreateContainer">
          <template #icon>
            <NIcon>
              <Add />
            </NIcon>
          </template>
          新建容器
        </NButton>
      </template>

      <template #actions>
        <div class="container-toolbar-filters">
          <NInput
            :value="controller.containerSearchKeyword"
            clearable
            class="container-search-input"
            placeholder="搜索容器"
            @update:value="controller.setContainerSearchKeyword"
          >
            <template #prefix><Search :size="16" /></template>
          </NInput>
          <NSelect
            :value="controller.containerStatusFilter"
            class="container-filter-select"
            :options="controller.containerStatusOptions"
            @update:value="controller.setContainerStatusFilter"
          />
          <NSelect
            :value="controller.containerComposeProjectFilter"
            class="container-compose-select"
            :options="controller.containerComposeProjectOptions"
            @update:value="controller.setContainerComposeProjectFilter"
          />
          <NTooltip>
            <template #trigger>
              <NButton
                circle
                :loading="controller.loading"
                aria-label="刷新容器"
                @click="controller.refreshContainers"
              >
                <template #icon><RefreshCw :size="16" /></template>
              </NButton>
            </template>
            刷新
          </NTooltip>
        </div>
      </template>
    </DockerTabToolbar>

    <NEmpty v-if="controller.containers.length === 0" class="my-auto" />
    <div v-else class="container-list app-scrollbar app-scrollbar-compact">
      <div class="container-list__summary">共 {{ controller.containerTotal }} 个容器</div>

      <article
        v-for="container in controller.containers"
        :key="container.id"
        class="container-card"
      >
        <div class="container-card__icon" aria-hidden="true">
          <Box :size="28" :stroke-width="1.8" />
        </div>

        <div class="container-card__content">
          <div class="container-card__heading">
            <strong :title="container.name">{{ container.name }}</strong>
            <NTooltip trigger="hover" placement="top-start">
              <template #trigger>
                <NTag size="small" :type="getContainerStatusPresentation(container).type">
                  {{ getContainerStatusPresentation(container).label }}
                </NTag>
              </template>
              <div class="grid max-w-[360px] gap-[5px]">
                <strong>{{ getContainerStatusPresentation(container).description }}</strong>
                <span class="break-anywhere opacity-72"
                  >详细状态：{{ container.status || '-' }}</span
                >
              </div>
            </NTooltip>
          </div>

          <div class="container-card__metadata">
            <span class="container-card__meta container-card__meta--wide" :title="container.image">
              <small>镜像</small>{{ container.image || '-' }}
            </span>
            <span class="container-card__meta" :title="container.composeProject || '独立容器'">
              <small>编排</small>{{ container.composeProject || '独立容器' }}
            </span>
            <span class="container-card__meta" :title="getContainerNetworksTitle(container)">
              <small>网络</small>{{ container.networks.map((item) => item.name).join(', ') || '-' }}
            </span>
            <span class="container-card__meta" :title="getContainerNetworkIpsTitle(container)">
              <small>IP</small
              >{{
                container.networks
                  .map((item) => item.ipAddress)
                  .filter(Boolean)
                  .join(', ') || '-'
              }}
            </span>
          </div>

          <div class="container-card__footer">
            <span class="container-card__id" :title="container.id">
              ID
              <CopyableText
                :text="container.id"
                :display-text="container.id.slice(0, 12)"
                success-message="已复制容器 ID。"
                error-message="复制容器 ID 失败。"
              />
            </span>
            <span>创建于 {{ controller.formatTime(container.createdAt) }}</span>
          </div>
        </div>

        <div class="container-card__actions">
          <NDropdown
            trigger="click"
            :options="getContainerPortOptions(container)"
            :disabled="container.ports.length === 0"
            @select="(key: string | number) => handleContainerRowMoreAction(container, String(key))"
          >
            <NTooltip>
              <template #trigger>
                <NButton
                  quaternary
                  circle
                  class="container-port-button"
                  :disabled="container.ports.length === 0"
                  aria-label="访问容器端口"
                >
                  <LogIn :size="16" />
                  <ChevronDown :size="12" />
                </NButton>
              </template>
              {{ container.ports.length ? '访问容器端口' : '没有可访问的端口' }}
            </NTooltip>
          </NDropdown>
          <NDropdown
            trigger="click"
            :options="getContainerRowMoreActionOptions(container)"
            @select="(key: string | number) => handleContainerRowMoreAction(container, String(key))"
          >
            <NButton quaternary circle aria-label="更多容器操作">
              <Ellipsis :size="19" />
            </NButton>
          </NDropdown>
          <NTooltip>
            <template #trigger>
              <NSwitch
                :value="container.state === 'running'"
                :aria-label="container.state === 'running' ? '停止容器' : '启动容器'"
                @update:value="toggleContainerState(container)"
              />
            </template>
            {{ container.state === 'running' ? '停止容器' : '启动容器' }}
          </NTooltip>
        </div>
      </article>
    </div>

    <div v-if="controller.containerTotal > 0" class="container-pagination">
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

    <NModal
      v-model:show="portActionVisible"
      preset="card"
      title="端口操作"
      style="width: min(460px, 92vw)"
    >
      <div class="port-action-content">
        <div>
          <span>容器</span>
          <strong>{{ selectedPortContainer?.name || '-' }}</strong>
        </div>
        <div>
          <span>端口映射</span>
          <strong>{{ selectedPort || '-' }}</strong>
        </div>
        <div>
          <span>访问地址</span>
          <strong :title="selectedPortUrl || '未映射宿主机端口'">
            {{ selectedPortUrl || '未映射宿主机端口' }}
          </strong>
        </div>
      </div>
      <template #action>
        <NSpace justify="end">
          <NButton @click="portActionVisible = false">取消</NButton>
          <NButton :disabled="!selectedPortUrl" @click="toggleSelectedPortPin">
            {{ selectedPortPinned ? '取消固定' : '固定到桌面' }}
          </NButton>
          <NButton type="primary" :disabled="!selectedPortUrl" @click="openSelectedPort">
            打开
          </NButton>
        </NSpace>
      </template>
    </NModal>
  </div>
</template>

<style scoped>
.container-search-input {
  width: min(280px, 30vw) !important;
  min-width: 180px;
  flex: none;
}

.container-toolbar-filters {
  display: flex;
  min-width: 0;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: 8px;
}

.container-filter-select {
  width: 124px;
}

.container-compose-select {
  width: 140px;
}

.container-list {
  display: flex;
  min-height: 0;
  flex: 1;
  flex-direction: column;
  gap: 12px;
  overflow: auto;
  padding: 1px 6px 8px 1px;
}

.container-list__summary {
  display: flex;
  flex: none;
  padding: 0 4px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
  font-size: 12px;
}

.container-card {
  display: grid;
  min-width: 0;
  grid-template-columns: 64px minmax(0, 1fr) auto;
  align-items: center;
  gap: 16px;
  border: 1px solid var(--docker-tab-card-border, rgba(148, 163, 184, 0.2));
  border-radius: 12px;
  background: var(--docker-card-background, transparent);
  padding: 20px;
  transition:
    border-color 0.2s ease,
    box-shadow 0.2s ease,
    transform 0.2s ease;
}

.container-card:hover {
  border-color: var(--app-primary-border);
  box-shadow: 0 8px 24px -20px rgba(var(--app-primary-rgb), 0.7);
  transform: translateY(-1px);
}

.container-card__icon {
  display: grid;
  width: 64px;
  height: 64px;
  place-items: center;
  border-radius: 12px;
  background: var(--app-primary-soft);
  color: var(--app-primary-color);
}

.container-card__content {
  min-width: 0;
}

.container-card__heading {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 10px;
}

.container-card__heading > strong {
  overflow: hidden;
  font-size: 17px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.container-card__metadata {
  display: grid;
  min-width: 0;
  grid-template-columns: minmax(180px, 1.6fr) repeat(3, minmax(100px, 1fr));
  margin-top: 10px;
}

.container-card__meta {
  min-width: 0;
  overflow: hidden;
  border-left: 1px solid var(--docker-tab-card-border, rgba(148, 163, 184, 0.2));
  padding: 0 14px;
  color: var(--docker-text-secondary, rgba(71, 85, 105, 0.88));
  text-overflow: ellipsis;
  white-space: nowrap;
}

.container-card__meta:first-child {
  border-left: 0;
  padding-left: 0;
}

.container-card__meta small {
  margin-right: 6px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
}

.container-card__footer {
  display: flex;
  min-width: 0;
  margin-top: 12px;
  flex-wrap: wrap;
  gap: 6px 18px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
  font-size: 12px;
}

.container-card__footer > span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.container-card__id {
  display: flex;
  align-items: center;
  gap: 5px;
}

.container-card__actions {
  display: flex;
  flex: none;
  align-items: center;
  gap: 8px;
}

.container-port-button {
  display: flex;
  align-items: center;
  gap: 1px;
}

.container-pagination {
  display: flex;
  flex: none;
  justify-content: flex-end;
  border-top: 1px solid var(--docker-tab-card-border, rgba(148, 163, 184, 0.2));
  padding-top: 10px;
}

.port-action-content {
  display: grid;
  gap: 12px;
}

.port-action-content > div {
  display: grid;
  min-width: 0;
  grid-template-columns: 88px minmax(0, 1fr);
  align-items: center;
  gap: 12px;
}

.port-action-content span {
  opacity: 0.62;
}

.port-action-content strong {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

@media (max-width: 1100px) {
  .container-card {
    grid-template-columns: 56px minmax(0, 1fr);
  }

  .container-card__icon {
    width: 56px;
    height: 56px;
  }

  .container-card__actions {
    grid-column: 2;
    justify-content: flex-end;
  }

  .container-card__metadata {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px 0;
  }

  .container-card__meta:nth-child(3) {
    border-left: 0;
    padding-left: 0;
  }
}

@media (max-width: 640px) {
  .container-toolbar-filters,
  .container-search-input {
    width: 100% !important;
  }

  .container-filter-select,
  .container-compose-select {
    min-width: 0;
    flex: 1;
  }

  .container-card {
    grid-template-columns: 48px minmax(0, 1fr);
    gap: 10px;
    padding: 14px 12px;
  }

  .container-card__icon {
    width: 48px;
    height: 48px;
  }

  .container-card__metadata {
    grid-template-columns: 1fr;
  }

  .container-card__meta,
  .container-card__meta:nth-child(3) {
    border-left: 0;
    padding: 3px 0;
  }

  .container-card__actions {
    grid-column: 2;
    gap: 8px;
  }

  .container-card__footer span:last-child {
    display: none;
  }
}
</style>

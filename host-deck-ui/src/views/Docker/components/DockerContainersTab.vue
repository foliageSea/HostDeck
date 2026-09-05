<script setup lang="ts">
import { computed, ref } from 'vue'
import { Add } from '@vicons/carbon'
import type { DockerContainer } from '@/api/docker'
import CopyableText from '@/components/common/CopyableText.vue'
import type { DockerViewController } from '../hooks/useDockerView'
import { getContainerStatusPresentation } from '../hooks/dockerViewHelpers'
import DockerResourceTable from './DockerResourceTable.vue'
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
    { key: 'stats', label: '监控', disabled: !isRunning },
    {
      key: 'ports',
      label: `端口 (${container.ports.length})`,
      disabled: container.ports.length === 0,
      children: container.ports.map((port) => ({
        key: `port:${port}`,
        label: port,
      })),
    },
    { key: 'logs', label: '日志' },
    { key: 'shell', label: '终端', disabled: !isRunning },
    { key: 'divider-1', type: 'divider' },
    { key: 'pause-toggle', label: paused ? '恢复' : '暂停', disabled: !isRunning },
    { key: 'inspect', label: '检查' },
    { key: 'edit', label: '编辑', disabled: isRunning },
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

function isContainerSelected(id: string) {
  return props.controller.selectedContainerIds.includes(id)
}

function toggleContainerSelection(id: string, checked: boolean) {
  const selectedIds = checked
    ? Array.from(new Set([...props.controller.selectedContainerIds, id]))
    : props.controller.selectedContainerIds.filter((item) => item !== id)

  props.controller.updateSelectedContainerIds(selectedIds)
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
        <div class="flex flex-wrap gap-1 items-center">
          <NInput
            :value="controller.containerSearchKeyword"
            clearable
            class="container-search-input"
            placeholder="搜索容器"
            @update:value="controller.setContainerSearchKeyword"
          />
          <NSelect
            :value="controller.containerStatusFilter"
            class="w-[128px]"
            :options="controller.containerStatusOptions"
            @update:value="controller.setContainerStatusFilter"
          />
          <NSelect
            :value="controller.containerComposeProjectFilter"
            class="w-[148px]"
            :options="controller.containerComposeProjectOptions"
            @update:value="controller.setContainerComposeProjectFilter"
          />
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
        <NDropdown
          trigger="click"
          :options="containerMoreActionOptions"
          @select="handleContainerMoreAction"
        >
          <NButton quaternary :loading="controller.batchProcessing">操作</NButton>
        </NDropdown>
        <NButton quaternary :loading="controller.loading" @click="controller.refreshContainers"
          >刷新</NButton
        >
      </template>

      <template #meta>
        <NTag round size="small">已选 {{ controller.selectedContainerIds.length }}</NTag>
      </template>
    </DockerTabToolbar>

    <NEmpty v-if="controller.containers.length === 0" />
    <DockerResourceTable v-else min-width="1460px">
      <thead>
        <tr>
          <th style="width: 44px"></th>
          <th style="width: 190px">容器</th>
          <th style="width: 150px">状态</th>
          <th style="width: 210px">镜像</th>
          <th style="width: 150px">编排</th>
          <th style="width: 180px">网络</th>
          <th style="width: 160px">IP</th>
          <th style="width: 190px">创建时间</th>
          <th class="docker-table-actions-column" style="width: 190px; text-align: right">操作</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="container in controller.containers" :key="container.id">
          <td>
            <NCheckbox
              :checked="isContainerSelected(container.id)"
              @update:checked="toggleContainerSelection(container.id, $event)"
            />
          </td>
          <td>
            <span class="docker-table-primary" :title="container.name">{{ container.name }}</span>
            <span class="docker-table-secondary" :title="container.id"
              ><CopyableText
                :text="container.id"
                :display-text="container.id.slice(0, 12)"
                success-message="已复制容器 ID。"
                error-message="复制容器 ID 失败。"
            /></span>
          </td>
          <td>
            <NTooltip trigger="hover" placement="top-start">
              <template #trigger>
                <div class="docker-table-status">
                  <NTag round size="small" :type="getContainerStatusPresentation(container).type">
                    {{ getContainerStatusPresentation(container).label }}
                  </NTag>
                </div>
              </template>
              <div class="grid max-w-[360px] gap-[5px]">
                <strong>{{ getContainerStatusPresentation(container).description }}</strong>
                <span class="break-anywhere opacity-72"
                  >详细状态：{{ container.status || '-' }}</span
                >
                <span class="break-anywhere opacity-72"
                  >引擎状态：{{ container.state || '-' }}</span
                >
              </div>
            </NTooltip>
          </td>
          <td>
            <span class="docker-table-primary" :title="container.image">{{ container.image }}</span>
          </td>
          <td>
            <span class="docker-table-primary" :title="container.composeProject || '-'">{{
              container.composeProject || '-'
            }}</span>
          </td>
          <td>
            <div class="docker-table-tags" :title="getContainerNetworksTitle(container)">
              <template v-if="container.networks.length"
                ><NTag
                  v-for="network in container.networks.slice(0, 2)"
                  :key="network.name"
                  size="small"
                  round
                  >{{ network.name }}</NTag
                ><span v-if="container.networks.length > 2"
                  >+{{ container.networks.length - 2 }}</span
                ></template
              ><template v-else>-</template>
            </div>
          </td>
          <td>
            <div class="docker-table-tags" :title="getContainerNetworkIpsTitle(container)">
              <template v-if="container.networks.some((item) => item.ipAddress)"
                ><NTag
                  v-for="network in container.networks.filter((item) => item.ipAddress).slice(0, 2)"
                  :key="`${network.name}-${network.ipAddress}`"
                  size="small"
                  round
                  type="info"
                  >{{ network.ipAddress }}</NTag
                ></template
              ><template v-else>-</template>
            </div>
          </td>
          <td class="docker-table-nowrap">{{ controller.formatTime(container.createdAt) }}</td>
          <td class="docker-table-actions-column">
            <div class="docker-table-actions">
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
              <NDropdown
                trigger="click"
                :options="getContainerRowMoreActionOptions(container)"
                @select="
                  (key: string | number) => handleContainerRowMoreAction(container, String(key))
                "
              >
                <NButton size="tiny" quaternary>更多</NButton>
              </NDropdown>
            </div>
          </td>
        </tr>
      </tbody>
      <template v-if="controller.containerTotal > 0" #footer>
        <NPagination
          :page="controller.containerPagination.page"
          :page-size="controller.containerPagination.pageSize"
          :item-count="controller.containerPagination.itemCount"
          :page-sizes="controller.containerPagination.pageSizes"
          show-size-picker
          @update:page="controller.handleContainerPageChange"
          @update:page-size="controller.handleContainerPageSizeChange"
        />
      </template>
    </DockerResourceTable>

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
  width: 220px !important;
  min-width: 220px;
  max-width: 220px;
  flex: none;
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
</style>

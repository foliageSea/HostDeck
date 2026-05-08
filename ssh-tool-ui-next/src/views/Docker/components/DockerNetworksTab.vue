<script setup lang="ts">
import type { SelectOption } from 'naive-ui'
import { reactive, ref } from 'vue'
import { dockerApi, type DockerContainer, type DockerNetwork } from '@/api/docker'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'

const props = defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()
const createVisible = ref(false)
const createSubmitting = ref(false)
const connectVisible = ref(false)
const connectSubmitting = ref(false)
const containerOptions = ref<SelectOption[]>([])
const containerOptionsLoading = ref(false)
const selectedNetwork = ref<DockerNetwork | null>(null)
const createOptionsText = ref('')
const createLabelsText = ref('')
let containerOptionsRequestId = 0
const networkDriverOptions = [
  { label: 'bridge', value: 'bridge' },
  { label: 'overlay', value: 'overlay' },
  { label: 'macvlan', value: 'macvlan' },
  { label: 'ipvlan', value: 'ipvlan' },
  { label: 'host', value: 'host' },
  { label: 'none', value: 'none' },
]
const createForm = reactive({
  name: '',
  driver: 'bridge',
  internal: false,
  attachable: false,
  ingress: false,
})
const connectForm = reactive({
  container: '',
  disconnect: false,
  force: false,
})

function openCreateDialog() {
  createForm.name = ''
  createForm.driver = 'bridge'
  createForm.internal = false
  createForm.attachable = false
  createForm.ingress = false
  createOptionsText.value = ''
  createLabelsText.value = ''
  createVisible.value = true
}

async function openConnectDialog(network: DockerNetwork, disconnect = false) {
  selectedNetwork.value = network
  connectForm.container = ''
  connectForm.disconnect = disconnect
  connectForm.force = false
  containerOptions.value = []
  connectVisible.value = true
  await loadContainerOptions(network, disconnect)
}

async function submitCreate() {
  if (!createForm.name.trim()) {
    return
  }

  createSubmitting.value = true
  try {
    const success = await props.controller.createNetwork({
      name: createForm.name.trim(),
      driver: createForm.driver.trim() || 'bridge',
      internal: createForm.internal,
      attachable: createForm.attachable,
      ingress: createForm.ingress,
      options: parseKeyValueMap(createOptionsText.value),
      labels: parseKeyValueMap(createLabelsText.value),
    })
    if (success) {
      createVisible.value = false
    }
  } finally {
    createSubmitting.value = false
  }
}

function parseKeyValueMap(value: string) {
  return Object.fromEntries(
    value
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        const index = line.indexOf('=')
        if (index < 1 || index === line.length - 1) {
          return null
        }

        return [line.slice(0, index).trim(), line.slice(index + 1).trim()] as const
      })
      .filter((entry): entry is readonly [string, string] => Boolean(entry && entry[0] && entry[1])),
  )
}

async function submitConnection() {
  if (!selectedNetwork.value || !connectForm.container.trim()) {
    return
  }

  connectSubmitting.value = true
  try {
    const success = await props.controller.updateNetworkConnection(
      selectedNetwork.value,
      connectForm.container.trim(),
      connectForm.disconnect,
      connectForm.force,
    )
    if (success) {
      connectVisible.value = false
    }
  } finally {
    connectSubmitting.value = false
  }
}

async function loadContainerOptions(network: DockerNetwork, disconnect: boolean) {
  const requestId = ++containerOptionsRequestId

  if (disconnect) {
    containerOptionsLoading.value = false
    containerOptions.value = (network.connectedContainerNames ?? []).map((name) => ({
      label: name,
      value: name,
    }))
    return
  }

  containerOptionsLoading.value = true
  try {
    const containers = await loadAllContainers()
    if (requestId !== containerOptionsRequestId || selectedNetwork.value?.id !== network.id || connectForm.disconnect !== disconnect) {
      return
    }

    const connectedNames = new Set(network.connectedContainerNames ?? [])
    containerOptions.value = containers
      .filter((container) => container.name && !connectedNames.has(container.name))
      .sort((left, right) => left.name.localeCompare(right.name, 'zh-CN'))
      .map((container) => ({
        label: `${container.name} (${container.state || 'unknown'})`,
        value: container.name,
      }))
  } catch (error) {
    console.error('Failed to load container options', error)
    getUiApi().message.error(error instanceof Error ? error.message : '加载容器列表失败。')
  } finally {
    if (requestId === containerOptionsRequestId) {
      containerOptionsLoading.value = false
    }
  }
}

async function loadAllContainers() {
  const connectionId = props.controller.requireConnectionId()
  const pageSize = 100
  let page = 1
  let totalPages = 1
  const containerMap = new Map<string, DockerContainer>()

  while (page <= totalPages) {
    const result = await dockerApi.listContainers(connectionId, {
      page,
      pageSize,
      status: 'all',
    })
    totalPages = result.totalPages
    result.items.forEach((container) => {
      containerMap.set(container.id, container)
    })
    page += 1
  }

  return Array.from(containerMap.values())
}

function getContainerSelectPlaceholder() {
  if (connectForm.disconnect) {
    return containerOptions.value.length ? '请选择要断开的容器' : '当前网络暂无已连接容器'
  }

  if (containerOptionsLoading.value) {
    return '正在加载容器列表'
  }

  return containerOptions.value.length ? '请选择要连接的容器' : '当前没有可连接的容器'
}

function getConnectedContainersTitle(network: DockerNetwork) {
  const names = network.connectedContainerNames ?? []
  return names.length ? names.join('\n') : '暂无已连接容器'
}
</script>

<template>
  <div class="flex flex-col gap-[12px]" :class="settingsStore.isDark ? 'docker-theme-dark' : 'docker-theme-light'">
    <div class="docker-toolbar">
      <div class="flex flex-wrap items-center justify-between gap-[12px]">
        <NSpace>
          <NButton type="primary" @click="openCreateDialog">新建网络</NButton>
          <NButton quaternary :loading="controller.loading" @click="controller.refreshNetworks">刷新网络</NButton>
          <NButton quaternary @click="controller.confirmPruneNetworks">清理未使用</NButton>
        </NSpace>
      </div>

      <div class="flex items-center gap-[8px] text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.58)]' : 'text-[rgba(100,116,139,0.82)]'">
        <NTag round size="small">网络 {{ controller.networks.length }}</NTag>
      </div>
    </div>

    <NEmpty v-if="controller.networks.length === 0" />

    <div v-else class="docker-card-list">
      <NCard
        v-for="network in controller.networks"
        :key="network.id"
        class="docker-card"
        content-class="docker-card-content"
        size="small"
        :bordered="false"
      >
        <template #header>
          <div class="min-w-0">
            <div class="truncate text-[15px] font-600" :title="network.name">{{ network.name }}</div>
            <div class="mt-[4px] truncate text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.58)]' : 'text-[rgba(100,116,139,0.88)]'" :title="network.id">
              {{ network.id.slice(0, 18) }}
            </div>
          </div>
        </template>

        <template #header-extra>
          <div class="flex flex-wrap justify-end gap-[6px]">
            <NTag round size="small">{{ network.driver }}</NTag>
            <NTag v-if="network.internal" round size="small" type="warning">Internal</NTag>
            <NTag v-if="network.attachable" round size="small" type="success">Attachable</NTag>
            <NTag v-if="network.ingress" round size="small" type="info">Ingress</NTag>
          </div>
        </template>

        <div class="docker-card-fields">
          <div class="docker-card-field">
            <span>作用域</span>
            <strong>{{ network.scope }}</strong>
          </div>
          <div class="docker-card-field">
            <span>已连接容器</span>
            <strong>{{ network.connectedContainers }}</strong>
          </div>
          <div class="docker-card-field wide">
            <span>容器名称</span>
            <div class="docker-chip-list" :title="getConnectedContainersTitle(network)">
              <template v-if="network.connectedContainerNames?.length">
                <NTag v-for="name in network.connectedContainerNames.slice(0, 4)" :key="name" size="small" round>
                  {{ name }}
                </NTag>
                <span v-if="network.connectedContainerNames.length > 4">等 {{ network.connectedContainerNames.length }} 个</span>
              </template>
              <template v-else>-</template>
            </div>
          </div>
          <div class="docker-card-field wide">
            <span>创建时间</span>
            <strong>{{ controller.formatTime(network.createdAt) }}</strong>
          </div>
        </div>

        <template #footer>
          <div class="docker-card-actions">
            <NButton size="tiny" quaternary @click="controller.viewNetworkInspect(network)">Inspect</NButton>
            <NButton size="tiny" quaternary @click="openConnectDialog(network, false)">连接容器</NButton>
            <NButton size="tiny" quaternary @click="openConnectDialog(network, true)">断开容器</NButton>
            <NButton size="tiny" quaternary type="error" @click="controller.confirmRemoveNetwork(network)">删除</NButton>
          </div>
        </template>
      </NCard>
    </div>

    <NModal v-model:show="createVisible" preset="card" title="新建 Docker 网络" style="width: min(560px, 92vw)">
      <NForm label-placement="top">
        <NFormItem label="网络名称">
          <NInput v-model:value="createForm.name" placeholder="例如 app-network" />
        </NFormItem>
        <NFormItem label="驱动">
          <NSelect v-model:value="createForm.driver" :options="networkDriverOptions" />
        </NFormItem>
        <NFormItem label="Driver Options">
          <NInput
            v-model:value="createOptionsText"
            type="textarea"
            :rows="3"
            placeholder="每行一条 key=value，例如 com.docker.network.bridge.enable_icc=true"
          />
        </NFormItem>
        <NFormItem label="Labels">
          <NInput
            v-model:value="createLabelsText"
            type="textarea"
            :rows="3"
            placeholder="每行一条 key=value，例如 app=ssh-tool"
          />
        </NFormItem>
        <div class="grid grid-cols-3 gap-[12px] lt-sm:grid-cols-1">
          <NFormItem label="Internal">
            <NSwitch v-model:value="createForm.internal" />
          </NFormItem>
          <NFormItem label="Attachable">
            <NSwitch v-model:value="createForm.attachable" />
          </NFormItem>
          <NFormItem label="Ingress">
            <NSwitch v-model:value="createForm.ingress" />
          </NFormItem>
        </div>
      </NForm>
      <template #action>
        <NSpace justify="end">
          <NButton @click="createVisible = false">取消</NButton>
          <NButton type="primary" :loading="createSubmitting" @click="submitCreate">创建</NButton>
        </NSpace>
      </template>
    </NModal>

    <NModal
      v-model:show="connectVisible"
      preset="card"
      :title="`${connectForm.disconnect ? '断开容器' : '连接容器'} · ${selectedNetwork?.name ?? ''}`"
      style="width: min(560px, 92vw)"
    >
      <NForm label-placement="top">
        <NFormItem label="容器">
          <NSelect
            v-model:value="connectForm.container"
            :options="containerOptions"
            :loading="containerOptionsLoading"
            :placeholder="getContainerSelectPlaceholder()"
            :disabled="containerOptionsLoading || containerOptions.length === 0"
            clearable
            filterable
          />
        </NFormItem>
        <NFormItem v-if="connectForm.disconnect" label="强制断开">
          <NSwitch v-model:value="connectForm.force" />
        </NFormItem>
      </NForm>
      <template #action>
        <NSpace justify="end">
          <NButton @click="connectVisible = false">取消</NButton>
          <NButton type="primary" :loading="connectSubmitting" :disabled="containerOptionsLoading || !connectForm.container" @click="submitConnection">
            {{ connectForm.disconnect ? '断开' : '连接' }}
          </NButton>
        </NSpace>
      </template>
    </NModal>
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
  --docker-toolbar-bg: rgba(15, 23, 42, 0.76);
  --docker-toolbar-border: rgba(148, 163, 184, 0.14);
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
  --docker-toolbar-bg: rgba(255, 255, 255, 0.8);
  --docker-toolbar-border: rgba(148, 163, 184, 0.18);
}

.docker-toolbar {
  position: sticky;
  top: 0;
  z-index: 2;
  display: flex;
  flex-direction: column;
  gap: 12px;
  border-bottom: 1px solid var(--docker-toolbar-border);
  background: transparent;
  padding: 2px 0 12px;
  backdrop-filter: none;
  padding: 8px;
}

.docker-card-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
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
  grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
  gap: 7px;
}

.docker-card-field {
  min-width: 0;
  border-radius: 10px;
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

.docker-chip-list {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px;
  color: var(--docker-card-value-color);
  font-size: 12px;
  font-weight: 500;
}

.docker-card-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

@media (max-width: 640px) {
  .docker-card-fields {
    grid-template-columns: 1fr;
  }
}
</style>

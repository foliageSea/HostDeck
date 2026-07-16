<script setup lang="ts">
import type { SelectOption } from 'naive-ui'
import { reactive, ref } from 'vue'
import { Add, Help } from '@vicons/carbon'
import { dockerApi, type DockerContainer, type DockerNetwork } from '@/api/docker'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'
import DockerTabToolbar from './DockerTabToolbar.vue'

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
      .filter((entry): entry is readonly [string, string] =>
        Boolean(entry && entry[0] && entry[1]),
      ),
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
    if (
      requestId !== containerOptionsRequestId ||
      selectedNetwork.value?.id !== network.id ||
      connectForm.disconnect !== disconnect
    ) {
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

function isBuiltInNetwork(network: DockerNetwork) {
  return ['bridge', 'host', 'none'].includes(network.name)
}
</script>

<template>
  <div
    class="flex h-full min-h-0 flex-col gap-[12px] overflow-hidden"
    :class="settingsStore.isDark ? 'docker-theme-dark' : 'docker-theme-light'"
  >
    <DockerTabToolbar>
      <template #left>
        <NInput
          v-model:value="controller.networkSearchKeyword"
          clearable
          class="w-[min(220px,60vw)] lt-sm:w-full"
          placeholder="搜索网络"
        />
      </template>

      <template #actions>
        <NButton type="primary" @click="openCreateDialog">
          <template #icon>
            <NIcon>
              <Add />
            </NIcon>
          </template>
          新建网络
        </NButton>
        <NButton quaternary :loading="controller.loading" @click="controller.refreshNetworks"
          >刷新</NButton
        >
        <NButton quaternary @click="controller.confirmPruneNetworks">清理未使用</NButton>
      </template>

      <template #meta>
        <NTag round size="small"
          >显示 {{ controller.filteredNetworks.length }} / {{ controller.networks.length }}</NTag
        >
      </template>
    </DockerTabToolbar>

    <NEmpty v-if="controller.filteredNetworks.length === 0" />

    <div v-else class="docker-card-list app-scrollbar app-scrollbar-compact">
      <NCard
        v-for="network in controller.filteredNetworks"
        :key="network.id"
        class="docker-card"
        content-class="docker-card-content"
        size="small"
        :bordered="false"
      >
        <template #header>
          <div class="min-w-0">
            <div class="truncate text-[15px] font-600" :title="network.name">
              {{ network.name }}
            </div>
            <div
              class="mt-[4px] truncate text-[12px]"
              :class="
                settingsStore.isDark
                  ? 'text-[rgba(226,232,240,0.58)]'
                  : 'text-[rgba(100,116,139,0.88)]'
              "
              :title="network.id"
            >
              {{ network.id.slice(0, 18) }}
            </div>
          </div>
        </template>

        <template #header-extra>
          <div class="flex flex-wrap justify-end gap-[6px]">
            <NTag round size="small">{{ network.driver }}</NTag>
            <NTag v-if="isBuiltInNetwork(network)" round size="small" type="info">系统网络</NTag>
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
          <div class="docker-card-field">
            <span>网关</span>
            <strong :title="network.gateway || '-'">{{ network.gateway || '-' }}</strong>
          </div>
          <div class="docker-card-field wide">
            <span>容器名称</span>
            <div class="docker-chip-list" :title="getConnectedContainersTitle(network)">
              <template v-if="network.connectedContainerNames?.length">
                <NTag
                  v-for="name in network.connectedContainerNames.slice(0, 4)"
                  :key="name"
                  size="small"
                  round
                >
                  {{ name }}
                </NTag>
                <span v-if="network.connectedContainerNames.length > 4"
                  >等 {{ network.connectedContainerNames.length }} 个</span
                >
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
            <NButton size="tiny" quaternary @click="controller.viewNetworkInspect(network)"
              >Inspect</NButton
            >
            <NButton size="tiny" quaternary @click="openConnectDialog(network, false)"
              >连接容器</NButton
            >
            <NButton size="tiny" quaternary @click="openConnectDialog(network, true)"
              >断开容器</NButton
            >
            <NButton
              size="tiny"
              quaternary
              type="error"
              :disabled="isBuiltInNetwork(network) || network.connectedContainers > 0"
              :title="
                isBuiltInNetwork(network)
                  ? 'Docker 初始网络不可删除'
                  : network.connectedContainers > 0
                    ? '请先断开已连接的容器'
                    : undefined
              "
              @click="controller.confirmRemoveNetwork(network)"
              >删除</NButton
            >
          </div>
        </template>
      </NCard>
    </div>

    <NModal
      v-model:show="createVisible"
      preset="card"
      title="新建 Docker 网络"
      style="width: min(560px, 92vw)"
    >
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
          <NFormItem>
            <template #label>
              <span class="docker-form-label-with-help">
                Internal
                <NTooltip trigger="hover" placement="top">
                  <template #trigger>
                    <NIcon class="docker-help-icon" :size="14">
                      <Help />
                    </NIcon>
                  </template>
                  内部网络。开启后容器通常只能在该网络内通信，适合数据库、缓存等不希望外部访问的服务。
                </NTooltip>
              </span>
            </template>
            <NSwitch v-model:value="createForm.internal" />
          </NFormItem>
          <NFormItem>
            <template #label>
              <span class="docker-form-label-with-help">
                Attachable
                <NTooltip trigger="hover" placement="top">
                  <template #trigger>
                    <NIcon class="docker-help-icon" :size="14">
                      <Help />
                    </NIcon>
                  </template>
                  允许独立容器加入。主要用于 overlay/Swarm
                  网络，开启后可手动把普通容器连接到该网络。
                </NTooltip>
              </span>
            </template>
            <NSwitch v-model:value="createForm.attachable" />
          </NFormItem>
          <NFormItem>
            <template #label>
              <span class="docker-form-label-with-help">
                Ingress
                <NTooltip trigger="hover" placement="top">
                  <template #trigger>
                    <NIcon class="docker-help-icon" :size="14">
                      <Help />
                    </NIcon>
                  </template>
                  Swarm 入口网络。用于 Swarm 服务端口发布和路由网格，普通 bridge 网络通常不要开启。
                </NTooltip>
              </span>
            </template>
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
          <NButton
            type="primary"
            :loading="connectSubmitting"
            :disabled="containerOptionsLoading || !connectForm.container"
            @click="submitConnection"
          >
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
  --docker-card-bg: transparent;
  --docker-card-shadow: none;
  --docker-card-border-hover: rgba(var(--app-primary-rgb), 0.42);
  --docker-card-bg-hover: transparent;
  --docker-card-field-bg: rgba(15, 23, 42, 0.38);
  --docker-card-label-color: rgba(226, 232, 240, 0.52);
  --docker-card-value-color: rgba(248, 250, 252, 0.9);
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
  grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
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

.docker-form-label-with-help {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.docker-help-icon {
  cursor: help;
  color: var(--docker-card-label-color);
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
  justify-content: flex-end;
  gap: 4px;
}

@media (max-width: 640px) {
  .docker-card-fields {
    grid-template-columns: 1fr;
  }
}
</style>

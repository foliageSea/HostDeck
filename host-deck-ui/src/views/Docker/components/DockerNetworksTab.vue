<script setup lang="ts">
import type { SelectOption } from 'naive-ui'
import { reactive, ref } from 'vue'
import { Add, Help } from '@vicons/carbon'
import { Ellipsis, Network, RefreshCw, Search } from '@lucide/vue'
import { dockerApi, type DockerContainer, type DockerNetwork } from '@/api/docker'
import CopyableText from '@/components/common/CopyableText.vue'
import { getUiApi } from '@/lib/ui'
import type { DockerViewController } from '../hooks/useDockerView'
import DockerTabToolbar from './DockerTabToolbar.vue'

const props = defineProps<{
  controller: DockerViewController
}>()

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

function getConnectedContainersText(network: DockerNetwork) {
  const names = network.connectedContainerNames ?? []
  if (names.length === 0) {
    return '-'
  }

  return names.length <= 3
    ? names.join('、')
    : `${names.slice(0, 3).join('、')} 等 ${names.length} 个`
}

function isBuiltInNetwork(network: DockerNetwork) {
  return ['bridge', 'host', 'none'].includes(network.name)
}

function getNetworkMoreActionOptions(network: DockerNetwork) {
  return [
    { key: 'disconnect', label: '断开容器' },
    {
      key: 'remove',
      label: '删除',
      disabled: isBuiltInNetwork(network) || network.connectedContainers > 0,
    },
  ]
}

function handleNetworkMoreAction(network: DockerNetwork, action: string) {
  switch (action) {
    case 'disconnect':
      openConnectDialog(network, true)
      break
    case 'remove':
      props.controller.confirmRemoveNetwork(network)
      break
  }
}
</script>

<template>
  <div class="flex h-full min-h-0 flex-col overflow-hidden">
    <DockerTabToolbar>
      <template #left>
        <NButton type="primary" @click="openCreateDialog">
          <template #icon>
            <NIcon>
              <Add />
            </NIcon>
          </template>
          新建网络
        </NButton>
      </template>

      <template #actions>
        <NInput
          v-model:value="controller.networkSearchKeyword"
          clearable
          class="network-search-input"
          placeholder="搜索网络"
        >
          <template #prefix><Search :size="16" /></template>
        </NInput>
        <NTooltip>
          <template #trigger>
            <NButton
              circle
              :loading="controller.loading"
              aria-label="刷新网络"
              @click="controller.refreshNetworks"
            >
              <template #icon><RefreshCw :size="16" /></template>
            </NButton>
          </template>
          刷新
        </NTooltip>
        <NButton @click="controller.confirmPruneNetworks">清理未使用</NButton>
      </template>
    </DockerTabToolbar>

    <NEmpty v-if="controller.filteredNetworks.length === 0" class="my-auto" />
    <div v-else class="network-list app-scrollbar app-scrollbar-compact">
      <div class="network-list__summary">共 {{ controller.filteredNetworks.length }} 个网络</div>

      <article
        v-for="network in controller.filteredNetworks"
        :key="network.id"
        class="network-card"
      >
        <div class="network-card__icon" aria-hidden="true">
          <Network :size="28" :stroke-width="1.8" />
        </div>

        <div class="network-card__content">
          <div class="network-card__heading">
            <strong :title="network.name">{{ network.name }}</strong>
            <NTag size="small">{{ network.driver }}</NTag>
            <NTag v-if="isBuiltInNetwork(network)" size="small" type="info">系统网络</NTag>
            <NTag v-if="network.internal" size="small" type="warning">Internal</NTag>
            <NTag v-if="network.attachable" size="small" type="success">Attachable</NTag>
            <NTag v-if="network.ingress" size="small" type="info">Ingress</NTag>
          </div>

          <div class="network-card__metadata">
            <span class="network-card__meta">
              <small>作用域</small>{{ network.scope || '-' }}
            </span>
            <span class="network-card__meta" :title="network.gateway || '-'">
              <small>网关</small>{{ network.gateway || '-' }}
            </span>
            <span class="network-card__meta">
              <small>容器</small>{{ network.connectedContainers }}
            </span>
            <span
              class="network-card__meta network-card__meta--wide"
              :title="getConnectedContainersTitle(network)"
            >
              <small>已连接</small>{{ getConnectedContainersText(network) }}
            </span>
          </div>

          <div class="network-card__footer">
            <span class="network-card__id" :title="network.id">
              ID
              <CopyableText
                :text="network.id"
                :display-text="network.id.slice(0, 12)"
                success-message="已复制网络 ID。"
                error-message="复制网络 ID 失败。"
              />
            </span>
            <span>创建于 {{ controller.formatTime(network.createdAt) }}</span>
          </div>
        </div>

        <div class="network-card__actions">
          <NButton text type="primary" @click="controller.viewNetworkInspect(network)"
            >检查</NButton
          >
          <NButton text type="primary" @click="openConnectDialog(network, false)">
            连接容器
          </NButton>
          <NDropdown
            trigger="click"
            :options="getNetworkMoreActionOptions(network)"
            @select="(action: string | number) => handleNetworkMoreAction(network, String(action))"
          >
            <NButton quaternary circle aria-label="更多网络操作">
              <Ellipsis :size="19" />
            </NButton>
          </NDropdown>
        </div>
      </article>
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
.docker-form-label-with-help {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.docker-help-icon {
  cursor: help;
  opacity: 0.6;
}

.network-search-input {
  width: min(320px, 36vw) !important;
  min-width: 200px;
}

.network-list {
  display: flex;
  min-height: 0;
  flex: 1;
  flex-direction: column;
  gap: 12px;
  overflow: auto;
  padding: 1px 6px 8px 1px;
}

.network-list__summary {
  display: flex;
  flex: none;
  padding: 0 4px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
  font-size: 12px;
}

.network-card {
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

.network-card:hover {
  border-color: var(--app-primary-border);
  box-shadow: 0 8px 24px -20px rgba(var(--app-primary-rgb), 0.7);
  transform: translateY(-1px);
}

.network-card__icon {
  display: grid;
  width: 64px;
  height: 64px;
  place-items: center;
  border-radius: 12px;
  background: var(--app-primary-soft);
  color: var(--app-primary-color);
}

.network-card__content {
  min-width: 0;
}

.network-card__heading {
  display: flex;
  min-width: 0;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}

.network-card__heading > strong {
  overflow: hidden;
  max-width: 100%;
  font-size: 17px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.network-card__metadata {
  display: grid;
  min-width: 0;
  grid-template-columns:
    minmax(90px, 0.6fr) minmax(140px, 1fr) minmax(80px, 0.45fr)
    minmax(180px, 1.6fr);
  margin-top: 10px;
}

.network-card__meta {
  min-width: 0;
  overflow: hidden;
  border-left: 1px solid var(--docker-tab-card-border, rgba(148, 163, 184, 0.2));
  padding: 0 14px;
  color: var(--docker-text-secondary, rgba(71, 85, 105, 0.88));
  text-overflow: ellipsis;
  white-space: nowrap;
}

.network-card__meta:first-child {
  border-left: 0;
  padding-left: 0;
}

.network-card__meta small {
  margin-right: 6px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
}

.network-card__footer {
  display: flex;
  min-width: 0;
  margin-top: 12px;
  flex-wrap: wrap;
  gap: 6px 18px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
  font-size: 12px;
}

.network-card__footer > span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.network-card__id {
  display: flex;
  align-items: center;
  gap: 5px;
}

.network-card__actions {
  display: flex;
  flex: none;
  align-items: center;
  gap: 16px;
}

@media (max-width: 1100px) {
  .network-card {
    grid-template-columns: 56px minmax(0, 1fr);
  }

  .network-card__icon {
    width: 56px;
    height: 56px;
  }

  .network-card__actions {
    grid-column: 2;
    justify-content: flex-end;
  }

  .network-card__metadata {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px 0;
  }

  .network-card__meta:nth-child(3) {
    border-left: 0;
    padding-left: 0;
  }
}

@media (max-width: 640px) {
  .network-search-input {
    width: calc(100% - 90px) !important;
    min-width: 0;
  }

  .network-card {
    grid-template-columns: 48px minmax(0, 1fr);
    gap: 10px;
    padding: 14px 12px;
  }

  .network-card__icon {
    width: 48px;
    height: 48px;
  }

  .network-card__metadata {
    grid-template-columns: 1fr;
  }

  .network-card__meta,
  .network-card__meta:nth-child(3) {
    border-left: 0;
    padding: 3px 0;
  }

  .network-card__actions {
    grid-column: 2;
    gap: 14px;
  }

  .network-card__footer span:last-child {
    display: none;
  }
}
</style>

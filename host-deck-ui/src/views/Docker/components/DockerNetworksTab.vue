<script setup lang="ts">
import type { SelectOption } from 'naive-ui'
import { reactive, ref } from 'vue'
import { Add, Help } from '@vicons/carbon'
import { dockerApi, type DockerContainer, type DockerNetwork } from '@/api/docker'
import { getUiApi } from '@/lib/ui'
import type { DockerViewController } from '../hooks/useDockerView'
import DockerResourceTable from './DockerResourceTable.vue'
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
  <div class="flex h-full min-h-0 flex-col gap-[12px] overflow-hidden">
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

    <DockerResourceTable v-else min-width="1460px">
      <thead>
        <tr>
          <th style="width: 220px">网络</th>
          <th style="width: 270px">类型</th>
          <th style="width: 90px">作用域</th>
          <th style="width: 100px">容器数</th>
          <th style="width: 150px">网关</th>
          <th style="width: 280px">容器名称</th>
          <th style="width: 190px">创建时间</th>
          <th class="docker-table-actions-column" style="width: 190px; text-align: right">操作</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="network in controller.filteredNetworks" :key="network.id">
          <td>
            <span class="docker-table-primary" :title="network.name">{{ network.name }}</span
            ><span class="docker-table-secondary" :title="network.id">{{
              network.id.slice(0, 18)
            }}</span>
          </td>
          <td>
            <div class="docker-table-tags">
              <NTag round size="small">{{ network.driver }}</NTag>
              <NTag v-if="isBuiltInNetwork(network)" round size="small" type="info">系统网络</NTag>
              <NTag v-if="network.internal" round size="small" type="warning">Internal</NTag>
              <NTag v-if="network.attachable" round size="small" type="success">Attachable</NTag>
              <NTag v-if="network.ingress" round size="small" type="info">Ingress</NTag>
            </div>
          </td>
          <td>{{ network.scope }}</td>
          <td>{{ network.connectedContainers }}</td>
          <td>
            <span class="docker-table-primary" :title="network.gateway || '-'">{{
              network.gateway || '-'
            }}</span>
          </td>
          <td>
            <div class="docker-table-tags" :title="getConnectedContainersTitle(network)">
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
          </td>
          <td class="docker-table-nowrap">{{ controller.formatTime(network.createdAt) }}</td>
          <td class="docker-table-actions-column">
            <div class="docker-table-actions">
              <NButton size="tiny" quaternary @click="controller.viewNetworkInspect(network)"
                >检查</NButton
              >
              <NButton size="tiny" quaternary @click="openConnectDialog(network, false)"
                >连接容器</NButton
              >
              <NDropdown
                trigger="click"
                :options="getNetworkMoreActionOptions(network)"
                @select="
                  (action: string | number) => handleNetworkMoreAction(network, String(action))
                "
              >
                <NButton size="tiny" quaternary>更多</NButton>
              </NDropdown>
            </div>
          </td>
        </tr>
      </tbody>
    </DockerResourceTable>

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
</style>

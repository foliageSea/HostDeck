<script setup lang="ts">
import { computed, h, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { Play, Renew, Search, Stop, TreeView } from '@vicons/carbon'
import { NButton, type DataTableColumns } from 'naive-ui'
import { processApi, type ProcessDetail, type ProcessInfo, type ProcessSignal, type ProcessSortBy, type ProcessSortOrder, type ProcessTreeNode } from '@/api/process'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

const props = defineProps<{
  connectionId?: string
  host?: string
  username?: string
  windowId?: string
}>()

type ProcessTab = 'list' | 'tree'

interface TreeOption extends Omit<ProcessTreeNode, 'children'> {
  children: TreeOption[]
  key: string
  label: string
}

const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const ui = getUiApi()

const activeTab = ref<ProcessTab>('list')
const loading = ref(false)
const detailLoading = ref(false)
const treeLoading = ref(false)
const actionLoadingPid = ref<number | null>(null)
const processes = ref<ProcessInfo[]>([])
const processTree = ref<ProcessTreeNode[]>([])
const selectedPid = ref<number | null>(null)
const selectedProcessDetail = ref<ProcessDetail | null>(null)
const detailVisible = ref(false)
const wsStatus = ref<'connecting' | 'connected' | 'reconnecting' | 'disconnected'>('disconnected')
const keyword = ref('')
const userFilter = ref('')
const sortBy = ref<ProcessSortBy>('cpu')
const sortOrder = ref<ProcessSortOrder>('desc')
const refreshAt = ref<Date | null>(null)
const showStartModal = ref(false)
const startSubmitting = ref(false)
const startCommand = ref('')
const startWorkingDirectory = ref('')
const startEnvironmentText = ref('')
let processWs: WebSocket | null = null
let reconnectTimer: number | null = null
let pingTimer: number | null = null
let isIntentionalClose = false

const connectionId = computed(() => props.connectionId ?? sshStore.connectionId ?? '')
const drawerWidth = computed(() => Math.min(520, window.innerWidth - 24))
const connectionLabel = computed(() => {
  const username = (props.username ?? sshStore.username).trim()
  const host = (props.host ?? sshStore.host).trim()
  return username && host ? `${username}@${host}` : '未连接'
})
const userOptions = computed(() => {
  const options = new Set<string>()
  for (const process of processes.value) {
    if (process.user.trim()) {
      options.add(process.user.trim())
    }
  }

  return Array.from(options)
    .sort((left, right) => left.localeCompare(right))
    .map((value) => ({ label: value, value }))
})
const processColumns: DataTableColumns<ProcessInfo> = [
  { title: 'PID', key: 'pid', width: 88 },
  { title: '用户', key: 'user', width: 120 },
  {
    title: 'CPU',
    key: 'cpuPercent',
    width: 88,
    render: (row: ProcessInfo) => `${row.cpuPercent.toFixed(1)}%`,
  },
  {
    title: '内存',
    key: 'memoryPercent',
    width: 88,
    render: (row: ProcessInfo) => `${row.memoryPercent.toFixed(1)}%`,
  },
  { title: '状态', key: 'state', width: 80 },
  { title: '运行时长', key: 'elapsed', width: 110 },
  { title: '命令', key: 'commandLine', ellipsis: { tooltip: true } },
  {
    title: '操作',
    key: 'actions',
    width: 240,
    render: (row: ProcessInfo) => h('div', { class: 'flex items-center gap-[8px]' }, [
      h(NButton, {
        size: 'tiny',
        quaternary: true,
        onClick: () => {
          void openDetail(row.pid)
        },
      }, { default: () => '详情' }),
      h(NButton, {
        size: 'tiny',
        quaternary: true,
        type: 'warning',
        loading: actionLoadingPid.value === row.pid,
        onClick: () => {
          void handleSignal(row, 'TERM')
        },
      }, { default: () => 'TERM' }),
      h(NButton, {
        size: 'tiny',
        quaternary: true,
        type: 'error',
        loading: actionLoadingPid.value === row.pid,
        onClick: () => {
          void handleSignal(row, 'KILL')
        },
      }, { default: () => 'KILL' }),
    ]),
  },
]

function buildTreeOptions(nodes: ProcessTreeNode[]): TreeOption[] {
  return nodes.map((node) => ({
    ...node,
    key: String(node.pid),
    label: `${node.pid} · ${node.command}`,
    children: buildTreeOptions(node.children),
  }))
}

const treeOptions = computed<TreeOption[]>(() => buildTreeOptions(processTree.value))

function formatRefreshAt(value: Date | null) {
  if (!value) {
    return '尚未刷新'
  }

  return new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(value)
}

function formatWsStatus(value: typeof wsStatus.value) {
  if (value === 'connected') {
    return '实时推送已连接'
  }

  if (value === 'reconnecting') {
    return '实时推送重连中'
  }

  if (value === 'connecting') {
    return '实时推送连接中'
  }

  return '实时推送已断开'
}

function stopProcessWs() {
  if (reconnectTimer !== null) {
    window.clearTimeout(reconnectTimer)
    reconnectTimer = null
  }

  if (pingTimer !== null) {
    window.clearInterval(pingTimer)
    pingTimer = null
  }

  if (processWs) {
    processWs.close(1000, 'Normal Closure')
    processWs = null
  }
}

function handleSnapshot(payload: unknown) {
  if (!payload || typeof payload !== 'object') {
    return
  }

  const message = payload as {
    code?: number
    data?: {
      detail?: ProcessDetail | null
      processes?: ProcessInfo[]
      refreshedAt?: number
      tree?: ProcessTreeNode[]
    }
    message?: string
  }

  if (message.code !== 200 || !message.data) {
    loading.value = false
    treeLoading.value = false
    if (message.message) {
      ui.message.error(message.message)
    }
    return
  }

  processes.value = message.data.processes ?? []
  if (Array.isArray(message.data.tree)) {
    processTree.value = message.data.tree
  }
  if (detailVisible.value && selectedPid.value !== null) {
    selectedProcessDetail.value = message.data.detail ?? null
    detailLoading.value = false
  }
  refreshAt.value = message.data.refreshedAt ? new Date(message.data.refreshedAt) : new Date()
  loading.value = false
  treeLoading.value = false
}

function sendWsFilters() {
  if (!processWs || processWs.readyState !== WebSocket.OPEN) {
    return
  }

  processWs.send(JSON.stringify({
    type: 'updateFilters',
    payload: {
      includeTree: activeTab.value === 'tree',
      keyword: keyword.value.trim() || undefined,
      selectedPid: detailVisible.value ? selectedPid.value : undefined,
      sortBy: sortBy.value,
      sortOrder: sortOrder.value,
      user: userFilter.value || undefined,
    },
  }))
}

function requestRefresh() {
  if (processWs?.readyState === WebSocket.OPEN) {
    loading.value = true
    if (activeTab.value === 'tree') {
      treeLoading.value = true
    }
    processWs.send('refresh')
  }
}

function startProcessWs() {
  stopProcessWs()
  if (!connectionId.value) {
    processes.value = []
    processTree.value = []
    wsStatus.value = 'disconnected'
    return
  }

  loading.value = true
  treeLoading.value = activeTab.value === 'tree'
  wsStatus.value = wsStatus.value === 'disconnected' ? 'connecting' : 'reconnecting'

  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  const query = new URLSearchParams({
    connectionId: connectionId.value,
    includeTree: activeTab.value === 'tree' ? 'true' : 'false',
    keyword: keyword.value.trim(),
    sortBy: sortBy.value,
    sortOrder: sortOrder.value,
    user: userFilter.value.trim(),
  })
  const wsUrl = `${protocol}//${window.location.host}/api/ws/processes?${query.toString()}`

  processWs = new WebSocket(wsUrl)

  processWs.onopen = () => {
    wsStatus.value = 'connected'
    loading.value = true
    if (activeTab.value === 'tree') {
      treeLoading.value = true
    }
    sendWsFilters()
  }

  processWs.onmessage = (event) => {
    if (event.data === 'pong') {
      return
    }

    try {
      handleSnapshot(JSON.parse(event.data) as unknown)
    } catch (error) {
      console.error('Failed to parse process WS message', error)
    }
  }

  processWs.onclose = () => {
    stopProcessWs()
    if (isIntentionalClose) {
      wsStatus.value = 'disconnected'
      return
    }

    wsStatus.value = 'reconnecting'
    reconnectTimer = window.setTimeout(() => {
      startProcessWs()
    }, 3000)
  }

  pingTimer = window.setInterval(() => {
    if (processWs?.readyState === WebSocket.OPEN) {
      processWs.send('ping')
    }
  }, 10000)
}

async function openDetail(pid: number, visible = true) {
  if (!connectionId.value) {
    return
  }

  selectedPid.value = pid
  selectedProcessDetail.value = null
  detailLoading.value = true
  if (visible) {
    detailVisible.value = true
  }

  sendWsFilters()
  if (wsStatus.value === 'connected') {
    requestRefresh()
  }
}

async function handleSignal(process: ProcessInfo, signal: ProcessSignal) {
  if (!connectionId.value) {
    return
  }

  const signalLabel = signal === 'KILL' ? '强制结束' : signal === 'TERM' ? '结束' : '重载'
  const dialog = ui.dialog.warning({
    title: `${signalLabel}进程`,
    content: `确认向 PID ${process.pid} (${process.command}) 发送 ${signal} 信号吗？`,
    positiveText: signal === 'KILL' ? '强制结束' : '确认',
    negativeText: '取消',
    onPositiveClick: async () => {
      actionLoadingPid.value = process.pid
      dialog.loading = true
      try {
        await processApi.sendSignal(connectionId.value, process.pid, signal)
        ui.message.success(`已向 PID ${process.pid} 发送 ${signal}。`)
        requestRefresh()
        if (selectedPid.value === process.pid) {
          detailLoading.value = true
        }
      } catch (error) {
        console.error('Failed to send process signal', error)
        ui.message.error(error instanceof Error ? error.message : '进程信号发送失败。')
      } finally {
        dialog.loading = false
        actionLoadingPid.value = null
      }
    },
  })
}

function parseEnvironmentText() {
  const result: Record<string, string> = {}
  for (const line of startEnvironmentText.value.split('\n')) {
    const trimmedLine = line.trim()
    if (!trimmedLine) {
      continue
    }

    const separatorIndex = trimmedLine.indexOf('=')
    if (separatorIndex <= 0) {
      throw new Error(`环境变量格式错误：${trimmedLine}`)
    }

    const key = trimmedLine.slice(0, separatorIndex).trim()
    const value = trimmedLine.slice(separatorIndex + 1).trim()
    if (!key) {
      throw new Error(`环境变量键不能为空：${trimmedLine}`)
    }

    result[key] = value
  }

  return result
}

async function submitStartProcess() {
  if (!connectionId.value) {
    return
  }

  const command = startCommand.value.trim()
  if (!command) {
    ui.message.warning('请输入启动命令。')
    return
  }

  startSubmitting.value = true
  try {
    const environment = parseEnvironmentText()
    const result = await processApi.start({
      command,
      connectionId: connectionId.value,
      environment,
      workingDirectory: startWorkingDirectory.value.trim() || undefined,
    })
    ui.message.success(`进程已启动，PID ${result.pid}。日志：${result.logPath}`)
    showStartModal.value = false
    startCommand.value = ''
    startWorkingDirectory.value = ''
    startEnvironmentText.value = ''
    await openDetail(result.pid)
  } catch (error) {
    console.error('Failed to start process', error)
    ui.message.error(error instanceof Error ? error.message : '启动进程失败。')
  } finally {
    startSubmitting.value = false
  }
}

watch(activeTab, async (value) => {
  if (value === 'tree') {
    treeLoading.value = true
  }
  sendWsFilters()
})

watch([keyword, userFilter, sortBy, sortOrder], () => {
  loading.value = true
  if (activeTab.value === 'tree') {
    treeLoading.value = true
  }
  sendWsFilters()
})

watch(detailVisible, (value) => {
  if (!value) {
    selectedPid.value = null
    selectedProcessDetail.value = null
    detailLoading.value = false
    sendWsFilters()
    return
  }

  if (selectedPid.value !== null) {
    detailLoading.value = true
    sendWsFilters()
    requestRefresh()
  }
})

watch(connectionId, async () => {
  selectedPid.value = null
  selectedProcessDetail.value = null
  detailVisible.value = false
  isIntentionalClose = false
  startProcessWs()
}, { immediate: true })

onMounted(() => {
  isIntentionalClose = false
  startProcessWs()
})

onBeforeUnmount(() => {
  isIntentionalClose = true
  stopProcessWs()
  wsStatus.value = 'disconnected'
})
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-[16px] overflow-hidden p-[18px]" :class="settingsStore.isDark
    ? 'bg-[linear-gradient(180deg,rgba(15,23,42,0.16),rgba(15,23,42,0.06))]'
    : 'bg-[linear-gradient(180deg,rgba(255,255,255,0.72),rgba(226,232,240,0.38))]'">
    <div class="flex flex-wrap items-start justify-between gap-[16px]">
      <div>
        <div class="mb-[6px] flex items-center gap-[8px]">
          <NIcon :size="20">
            <TreeView />
          </NIcon>
          <h2 class="m-0 text-[20px]">进程管理</h2>
        </div>
        <div :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">
          当前连接：{{ connectionLabel }}
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-[10px]">
        <NTag round size="small">{{ formatWsStatus(wsStatus) }}</NTag>
        <NTag round size="small">最近刷新 {{ formatRefreshAt(refreshAt) }}</NTag>
        <NButton quaternary :loading="loading || treeLoading" :disabled="wsStatus !== 'connected'"
          @click="requestRefresh">
          <template #icon>
            <NIcon>
              <Renew />
            </NIcon>
          </template>
          刷新
        </NButton>
        <NButton type="primary" @click="showStartModal = true">
          <template #icon>
            <NIcon>
              <Play />
            </NIcon>
          </template>
          启动进程
        </NButton>
      </div>
    </div>

    <div class="grid grid-cols-[minmax(0,1fr)_240px_auto_auto] gap-[12px] lt-lg:grid-cols-1">
      <NInput v-model:value="keyword" clearable placeholder="搜索 PID / 用户 / 命令" @keyup.enter="requestRefresh">
        <template #prefix>
          <NIcon>
            <Search />
          </NIcon>
        </template>
      </NInput>
      <NSelect v-model:value="userFilter" clearable :options="userOptions" placeholder="按用户筛选" />
      <NSelect v-model:value="sortBy" :options="[
        { label: '按 CPU', value: 'cpu' },
        { label: '按内存', value: 'memory' },
        { label: '按 PID', value: 'pid' },
        { label: '按用户', value: 'user' },
        { label: '按命令', value: 'command' },
      ]" class="w-[120px]" />
      <NSelect v-model:value="sortOrder" :options="[
        { label: '降序', value: 'desc' },
        { label: '升序', value: 'asc' },
      ]" class="w-[100px]" />
    </div>

    <NTabs v-model:value="activeTab" animated type="line" class="process-tabs min-h-0 flex-1">
      <NTabPane name="list" tab="进程列表" class="h-full min-h-0">
        <NCard :bordered="false" class="process-card h-full min-h-0 rounded-[18px]"
          :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.82)]'">
          <NSpin :show="loading" class="h-full min-h-0">
            <NEmpty v-if="!loading && processes.length === 0" description="未找到匹配进程"
              class="h-full min-h-[240px] justify-center" />
            <div v-else class="process-table-shell">
              <NDataTable class="process-table" :bordered="false" :single-line="false" :pagination="{ pageSize: 12 }"
                :columns="processColumns" :data="processes" flex-height />
            </div>
          </NSpin>
        </NCard>
      </NTabPane>

      <NTabPane name="tree" tab="进程树" class="h-full min-h-0 overflow-auto app-scrollbar">
        <NCard :bordered="false" class="process-card h-full min-h-0 rounded-[18px] overflow-auto"
          :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.82)]'">
          <NSpin :show="treeLoading" class="h-full min-h-0">
            <NEmpty v-if="!treeLoading && treeOptions.length === 0" description="没有可展示的进程树"
              class="h-full min-h-[240px] justify-center" />
            <div v-else class="process-tree-shell "
              :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'">
              <NTree block-line block-node :data="treeOptions" selectable key-field="key" label-field="label"
                children-field="children" class="process-tree"
                @update:selected-keys="(keys: Array<string | number>) => { const pid = Number(keys[0]); if (pid) { void openDetail(pid) } }" />
            </div>
          </NSpin>
        </NCard>
      </NTabPane>
    </NTabs>

    <NDrawer v-model:show="detailVisible" :width="drawerWidth" placement="right">
      <NDrawerContent title="进程详情" closable>
        <NSpin :show="detailLoading">
          <NEmpty v-if="!selectedProcessDetail" :description="selectedPid ? '该进程已结束或当前用户无权限查看。' : '请选择一个进程'" />
          <div v-else class="grid gap-[14px]">
            <div class="grid grid-cols-2 gap-[12px]">
              <NCard size="small" title="PID">
                <div class="text-[20px] font-700">{{ selectedProcessDetail.pid }}</div>
              </NCard>
              <NCard size="small" title="PPID">
                <div class="text-[20px] font-700">{{ selectedProcessDetail.ppid }}</div>
              </NCard>
              <NCard size="small" title="CPU">
                <div class="text-[20px] font-700">{{ selectedProcessDetail.cpuPercent.toFixed(1) }}%</div>
              </NCard>
              <NCard size="small" title="内存">
                <div class="text-[20px] font-700">{{ selectedProcessDetail.memoryPercent.toFixed(1) }}%</div>
              </NCard>
            </div>

            <NDescriptions bordered label-placement="left" :column="1" size="small">
              <NDescriptionsItem label="用户">{{ selectedProcessDetail.user }}</NDescriptionsItem>
              <NDescriptionsItem label="状态">{{ selectedProcessDetail.state }}</NDescriptionsItem>
              <NDescriptionsItem label="命令">{{ selectedProcessDetail.command }}</NDescriptionsItem>
              <NDescriptionsItem label="TTY">{{ selectedProcessDetail.tty }}</NDescriptionsItem>
              <NDescriptionsItem label="PGID">{{ selectedProcessDetail.pgid }}</NDescriptionsItem>
              <NDescriptionsItem label="SID">{{ selectedProcessDetail.sid }}</NDescriptionsItem>
              <NDescriptionsItem label="启动时间">{{ selectedProcessDetail.startTime }}</NDescriptionsItem>
              <NDescriptionsItem label="运行时长">{{ selectedProcessDetail.elapsed }}</NDescriptionsItem>
              <NDescriptionsItem label="命令行">{{ selectedProcessDetail.commandLine }}</NDescriptionsItem>
            </NDescriptions>

            <div class="flex gap-[10px]">
              <NButton secondary type="warning" :loading="actionLoadingPid === selectedProcessDetail.pid"
                @click="handleSignal(selectedProcessDetail, 'TERM')">
                <template #icon>
                  <NIcon>
                    <Stop />
                  </NIcon>
                </template>
                TERM
              </NButton>
              <NButton secondary type="error" :loading="actionLoadingPid === selectedProcessDetail.pid"
                @click="handleSignal(selectedProcessDetail, 'KILL')">
                强制结束
              </NButton>
              <NButton quaternary @click="detailLoading = true; requestRefresh()">刷新详情</NButton>
            </div>
          </div>
        </NSpin>
      </NDrawerContent>
    </NDrawer>

    <NModal v-model:show="showStartModal" preset="card" title="启动新进程" style="width: min(720px, 94vw)">
      <NForm label-placement="top">
        <NFormItem label="启动命令">
          <NInput v-model:value="startCommand" type="textarea" :autosize="{ minRows: 3, maxRows: 6 }"
            placeholder="例如：python app.py --port 8080" />
        </NFormItem>
        <NFormItem label="工作目录">
          <NInput v-model:value="startWorkingDirectory" placeholder="例如：/srv/app" />
        </NFormItem>
        <NFormItem label="环境变量">
          <NInput v-model:value="startEnvironmentText" type="textarea" :autosize="{ minRows: 4, maxRows: 8 }"
            placeholder="每行一个 KEY=value" />
        </NFormItem>
      </NForm>

      <template #action>
        <div class="flex justify-end gap-[10px]">
          <NButton @click="showStartModal = false">取消</NButton>
          <NButton type="primary" :loading="startSubmitting" @click="submitStartProcess">启动</NButton>
        </div>
      </template>
    </NModal>
  </div>
</template>

<style scoped>
.process-tabs {
  height: 100%;
  min-height: 0;
}

.process-tabs :deep(.n-tabs-wrapper),
.process-tabs :deep(.n-tabs-content-holder),
.process-tabs :deep(.n-tabs-content) {
  flex: 1;
  width: 100%;
  min-height: 0;
}

.process-tabs :deep(.n-tabs-content-holder),
.process-tabs :deep(.n-tabs-content),
.process-tabs :deep(.n-tabs-pane-wrapper),
.process-tabs :deep(.n-tab-pane) {
  height: 100%;
  min-height: 0;
}

.process-tabs :deep(.n-tabs-pane-wrapper) {
  overflow: hidden;
}

.process-card :deep(.n-card__content) {
  display: flex;
  height: 100%;
  min-height: 0;
  flex-direction: column;
  overflow: hidden;
}

.process-card :deep(.n-spin-container),
.process-card :deep(.n-spin-content) {
  height: 100%;
  min-height: 0;
  overflow: hidden;
}

.process-card :deep(.n-spin-content) {
  display: flex;
  flex-direction: column;
}

.process-table-shell {
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

.process-table {
  height: 100%;
  min-height: 0;
}

.process-tree-shell {
  flex: 1;
  min-height: 0;
}

.process-tree {
  min-width: max-content;
}
</style>

<script setup lang="ts">
import { computed, h, onBeforeUnmount, onMounted, ref } from 'vue'
import { NDataTable, NTag, type DataTableColumns } from 'naive-ui'
import { runtimeApi } from '@/api/runtime'
import type {
  RuntimeClientSummary,
  RuntimeSessionPurpose,
  RuntimeSessionSummary,
  RuntimeSnapshot,
} from '@/api/runtime'
import { useSettingsStore } from '@/stores/settings'

const settingsStore = useSettingsStore()

interface RuntimeClientRow {
  connectionId: string
  isClosed: boolean
  sessionCount: number
  sessions: RuntimeSessionSummary[]
  isSynthetic: boolean
}

const loading = ref(false)
const refreshAt = ref<Date | null>(null)
const snapshot = ref<RuntimeSnapshot | null>(null)
const streamStatus = ref<'connecting' | 'connected' | 'reconnecting' | 'disconnected'>(
  'disconnected',
)
let runtimeSource: EventSource | null = null
let isIntentionalClose = false

const clients = computed<RuntimeClientSummary[]>(() => snapshot.value?.clients ?? [])
const sessions = computed<RuntimeSessionSummary[]>(() => snapshot.value?.sessions ?? [])
const purposeLabels: Record<RuntimeSessionPurpose, string> = {
  terminal: '终端',
  fileManagement: '文件管理',
  fileTask: '文件任务',
  docker: 'Docker 管理',
  dockerCompose: 'Docker Compose',
  containerShell: '容器终端',
  systemMonitor: '系统监控',
  agent: 'Agent 操作',
  cronTask: '定时任务',
  processManagement: '进程管理',
}
const sessionColumns: DataTableColumns<RuntimeSessionSummary> = [
  { title: 'Session ID', key: 'sessionId' },
  {
    title: '用途',
    key: 'purposes',
    render: (row) => {
      if (row.purposes.length === 0) {
        return '未标注'
      }

      return h(
        'div',
        { class: 'flex flex-wrap gap-[6px]' },
        row.purposes.map((purpose) =>
          h(
            NTag,
            { key: purpose, size: 'small', bordered: false },
            { default: () => purposeLabels[purpose] ?? purpose },
          ),
        ),
      )
    },
  },
  { title: '类型', key: 'type' },
  { title: 'Shell', key: 'hasShell', render: (row) => (row.hasShell ? '是' : '否') },
  {
    title: 'Client 状态',
    key: 'clientClosed',
    render: (row) => (row.clientClosed ? '已关闭' : '活跃'),
  },
]
const clientRows = computed<RuntimeClientRow[]>(() => {
  const groupedSessions = new Map<string, RuntimeSessionSummary[]>()

  for (const session of sessions.value) {
    const currentSessions = groupedSessions.get(session.connectionId) ?? []
    currentSessions.push(session)
    groupedSessions.set(session.connectionId, currentSessions)
  }

  const rows = clients.value.map((client) => {
    const clientSessions = groupedSessions.get(client.connectionId) ?? []
    groupedSessions.delete(client.connectionId)

    return {
      connectionId: client.connectionId,
      isClosed: client.isClosed,
      sessionCount: clientSessions.length > 0 ? clientSessions.length : client.sessionCount,
      sessions: clientSessions,
      isSynthetic: false,
    }
  })

  for (const [connectionId, orphanSessions] of groupedSessions.entries()) {
    rows.push({
      connectionId,
      isClosed: orphanSessions.every((session) => session.clientClosed),
      sessionCount: orphanSessions.length,
      sessions: orphanSessions,
      isSynthetic: true,
    })
  }

  return rows.sort(
    (left, right) =>
      right.sessionCount - left.sessionCount || left.connectionId.localeCompare(right.connectionId),
  )
})
const clientColumns: DataTableColumns<RuntimeClientRow> = [
  {
    type: 'expand',
    expandable: (row) => row.sessions.length > 0,
    renderExpand: (row) =>
      h('div', { class: 'runtime-session-expand' }, [
        h(NDataTable, {
          bordered: false,
          singleLine: false,
          columns: sessionColumns,
          data: row.sessions,
          pagination: false,
          size: 'small',
        }),
      ]),
  },
  { title: 'Connection ID', key: 'connectionId' },
  { title: '状态', key: 'isClosed', render: (row) => (row.isClosed ? '已关闭' : '活跃') },
  {
    title: '数据来源',
    key: 'isSynthetic',
    render: (row) => (row.isSynthetic ? '仅 session 快照' : 'client 快照'),
  },
  { title: '关联 Session', key: 'sessionCount' },
]

function stopRuntimeStream() {
  if (runtimeSource) {
    runtimeSource.close()
    runtimeSource = null
  }
}

function handleSnapshot(payload: unknown) {
  if (!payload || typeof payload !== 'object') {
    return
  }

  snapshot.value = payload as RuntimeSnapshot
  refreshAt.value = new Date()
  loading.value = false
}

function startRuntimeStream() {
  stopRuntimeStream()
  loading.value = true
  streamStatus.value = streamStatus.value === 'disconnected' ? 'connecting' : 'reconnecting'

  const source = new EventSource('/api/runtime/sessions/stream')
  runtimeSource = source
  source.onopen = () => {
    streamStatus.value = 'connected'
    loading.value = false
  }

  source.addEventListener('snapshot', (event) => {
    try {
      handleSnapshot(JSON.parse((event as MessageEvent<string>).data) as unknown)
    } catch (error) {
      console.error('Failed to parse runtime SSE message', error)
    }
  })

  source.addEventListener('snapshot-error', (event) => {
    console.error('Runtime SSE snapshot failed', (event as MessageEvent<string>).data)
  })

  source.onerror = () => {
    if (isIntentionalClose || source !== runtimeSource) {
      return
    }

    streamStatus.value = 'reconnecting'
    loading.value = false
  }
}

async function requestRefresh() {
  loading.value = true
  try {
    handleSnapshot(await runtimeApi.getSessions())
  } catch (error) {
    console.error('Failed to refresh runtime sessions', error)
  } finally {
    loading.value = false
  }
}

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

function formatStreamStatus(value: typeof streamStatus.value) {
  if (value === 'connected') {
    return '实时连接已建立'
  }

  if (value === 'reconnecting') {
    return '实时连接重连中'
  }

  if (value === 'connecting') {
    return '实时连接建立中'
  }

  return '实时连接已断开'
}

onMounted(() => {
  isIntentionalClose = false
  startRuntimeStream()
})

onBeforeUnmount(() => {
  isIntentionalClose = true
  stopRuntimeStream()
  streamStatus.value = 'disconnected'
})
</script>

<template>
  <div
    class="runtime-view flex h-full flex-col gap-[16px] overflow-auto p-[20px]"
    :class="
      settingsStore.isDark
        ? 'bg-[linear-gradient(180deg,rgba(15,23,42,0.14),rgba(15,23,42,0.04))]'
        : 'bg-[linear-gradient(180deg,rgba(255,255,255,0.68),rgba(226,232,240,0.34))]'
    "
  >
    <div class="flex items-start justify-between gap-[12px] lt-md:flex-col lt-md:items-stretch">
      <div>
        <div class="text-[24px] font-700">运行态会话</div>
      </div>

      <div class="flex items-center gap-[12px] lt-md:justify-between">
        <span
          class="text-[12px]"
          :class="
            settingsStore.isDark ? 'text-[rgba(96,165,250,0.92)]' : 'text-[rgba(37,99,235,0.92)]'
          "
        >
          {{ formatStreamStatus(streamStatus) }}
        </span>
        <span
          class="text-[12px]"
          :class="
            settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'
          "
        >
          最近刷新：{{ formatRefreshAt(refreshAt) }}
        </span>
        <NButton secondary :loading="loading" @click="requestRefresh">立即刷新</NButton>
      </div>
    </div>

    <div class="grid grid-cols-[repeat(2,minmax(0,1fr))] gap-[16px] lt-md:grid-cols-1">
      <NCard
        :bordered="false"
        class="app-radius-card rounded-[18px]"
        :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.82)]'"
      >
        <div
          class="text-[13px]"
          :class="
            settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'
          "
        >
          Clients
        </div>
        <div class="mt-[8px] text-[34px] font-700">{{ snapshot?.totalClients ?? 0 }}</div>
      </NCard>

      <NCard
        :bordered="false"
        class="app-radius-card rounded-[18px]"
        :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.82)]'"
      >
        <div
          class="text-[13px]"
          :class="
            settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'
          "
        >
          Sessions
        </div>
        <div class="mt-[8px] text-[34px] font-700">{{ snapshot?.totalSessions ?? 0 }}</div>
      </NCard>
    </div>

    <div class="flex-1 min-h-0">
      <NCard
        title="Clients / Sessions"
        :bordered="false"
        class="app-radius-card rounded-[18px] min-h-0"
        :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.82)]'"
      >
        <NDataTable
          :bordered="false"
          :single-line="false"
          :pagination="{ pageSize: 10 }"
          :columns="clientColumns"
          :data="clientRows"
          :loading="loading"
        />
      </NCard>
    </div>
  </div>
</template>

<style scoped>
.runtime-session-expand {
  padding: 8px 0 4px;
}
</style>

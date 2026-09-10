<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { RefreshCw } from '@lucide/vue'
import { Background } from '@vue-flow/background'
import { Controls } from '@vue-flow/controls'
import { Handle, Position, VueFlow, useVueFlow } from '@vue-flow/core'
import type { Edge, Node } from '@vue-flow/core'
import '@vue-flow/core/dist/style.css'
import '@vue-flow/core/dist/theme-default.css'
import '@vue-flow/controls/dist/style.css'
import { runtimeApi } from '@/api/runtime'
import type {
  RuntimeClientSummary,
  RuntimeSessionPurpose,
  RuntimeSessionSummary,
  RuntimeSnapshot,
} from '@/api/runtime'
import { useSettingsStore } from '@/stores/settings'

const settingsStore = useSettingsStore()
const { fitView } = useVueFlow({ id: 'runtime-sessions' })

interface RuntimeClientRow {
  connectionId: string
  isClosed: boolean
  sessionCount: number
  sessions: RuntimeSessionSummary[]
  isSynthetic: boolean
}

interface RuntimeNodeData {
  connectionId: string
  isClosed: boolean
  sessionCount: number
  isSynthetic: boolean
  sessionId?: string
  type?: RuntimeSessionSummary['type']
  purposes?: RuntimeSessionPurpose[]
  hasShell?: boolean
}

const loading = ref(false)
const refreshAt = ref<Date | null>(null)
const snapshot = ref<RuntimeSnapshot | null>(null)
const streamStatus = ref<'connecting' | 'connected' | 'reconnecting' | 'disconnected'>(
  'disconnected',
)
const hasFittedInitialSnapshot = ref(false)
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
      Number(left.isClosed) - Number(right.isClosed) ||
      right.sessionCount - left.sessionCount ||
      left.connectionId.localeCompare(right.connectionId),
  )
})

const flowNodes = computed<Node<RuntimeNodeData>[]>(() => {
  if (!snapshot.value) {
    return []
  }

  const nodes: Node<RuntimeNodeData>[] = []
  let groupTop = 32

  const contentHeight = Math.max(
    clientRows.value.reduce(
      (height, client, index) =>
        height + Math.max(client.sessions.length * 140 - 16, 96) + (index > 0 ? 48 : 0),
      0,
    ),
    96,
  )

  nodes.push({
    id: 'backend',
    type: 'backend',
    position: { x: 32, y: 32 + (contentHeight - 96) / 2 },
    data: {
      connectionId: 'HostDeck Service',
      isClosed: streamStatus.value === 'disconnected',
      sessionCount: snapshot.value.totalClients,
      isSynthetic: false,
    },
    draggable: false,
    selectable: false,
    connectable: false,
  })

  for (const client of clientRows.value) {
    const sessionAreaHeight = Math.max(client.sessions.length * 140 - 16, 96)
    nodes.push({
      id: `client:${client.connectionId}`,
      type: 'client',
      position: { x: 378, y: groupTop + (sessionAreaHeight - 96) / 2 },
      data: {
        connectionId: client.connectionId,
        isClosed: client.isClosed,
        sessionCount: client.sessionCount,
        isSynthetic: client.isSynthetic,
      },
      draggable: false,
      selectable: false,
      connectable: false,
    })

    client.sessions.forEach((session, index) => {
      nodes.push({
        id: `session:${session.sessionId}`,
        type: 'session',
        position: { x: 776, y: groupTop + index * 140 },
        data: {
          connectionId: session.connectionId,
          isClosed: session.clientClosed,
          sessionCount: 0,
          isSynthetic: false,
          sessionId: session.sessionId,
          type: session.type,
          purposes: session.purposes,
          hasShell: session.hasShell,
        },
        draggable: false,
        selectable: false,
        connectable: false,
      })
    })

    groupTop += sessionAreaHeight + 48
  }

  return nodes
})

const flowEdges = computed<Edge[]>(() => [
  ...clientRows.value.map((client) => ({
    id: `edge:backend:${client.connectionId}`,
    source: 'backend',
    target: `client:${client.connectionId}`,
    type: 'smoothstep',
    animated: !client.isClosed,
    style: {
      stroke: client.isClosed ? '#94a3b8' : '#22c55e',
      strokeWidth: 1.8,
    },
  })),
  ...clientRows.value.flatMap((client) =>
    client.sessions.map((session) => ({
      id: `edge:${client.connectionId}:${session.sessionId}`,
      source: `client:${client.connectionId}`,
      target: `session:${session.sessionId}`,
      type: 'smoothstep',
      animated: !client.isClosed && !session.clientClosed,
      style: {
        stroke: client.isClosed || session.clientClosed ? '#94a3b8' : '#22c55e',
        strokeWidth: 1.8,
      },
    })),
  ),
])

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

function handleNodesInitialized() {
  if (hasFittedInitialSnapshot.value || flowNodes.value.length === 0) {
    return
  }

  hasFittedInitialSnapshot.value = true
  void fitView({ padding: 0.16, maxZoom: 1, duration: 280 })
}

function formatPurpose(purpose: RuntimeSessionPurpose) {
  return purposeLabels[purpose] ?? purpose
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
    class="runtime-view flex h-full min-h-0 flex-col"
    :class="{ 'is-dark': settingsStore.isDark }"
  >
    <header class="runtime-header">
      <div class="min-w-0">
        <h1 class="m-0 text-[20px] font-700">运行态会话</h1>
        <div class="mt-[5px] flex flex-wrap items-center gap-x-[14px] gap-y-[4px] text-[12px]">
          <span class="stream-state" :data-state="streamStatus">
            <i aria-hidden="true"></i>{{ formatStreamStatus(streamStatus) }}
          </span>
          <span class="secondary-text">最近刷新：{{ formatRefreshAt(refreshAt) }}</span>
        </div>
      </div>

      <div class="flex shrink-0 items-center gap-[16px]">
        <div class="runtime-metric">
          <span>Clients</span>
          <strong>{{ snapshot?.totalClients ?? 0 }}</strong>
        </div>
        <div class="runtime-metric">
          <span>Sessions</span>
          <strong>{{ snapshot?.totalSessions ?? 0 }}</strong>
        </div>
        <NTooltip>
          <template #trigger>
            <NButton
              circle
              secondary
              :loading="loading"
              aria-label="立即刷新"
              @click="requestRefresh"
            >
              <template #icon><RefreshCw :size="16" /></template>
            </NButton>
          </template>
          立即刷新
        </NTooltip>
      </div>
    </header>

    <main class="runtime-canvas">
      <VueFlow
        id="runtime-sessions"
        :nodes="flowNodes"
        :edges="flowEdges"
        :min-zoom="0.25"
        :max-zoom="1.5"
        :zoom-on-double-click="false"
        :delete-key-code="null"
        @nodes-initialized="handleNodesInitialized"
      >
        <Background :gap="20" :size="1" :color="settingsStore.isDark ? '#334155' : '#cbd5e1'" />
        <Controls position="bottom-left" />

        <template #node-backend="{ data }">
          <article class="flow-node backend-node" :class="{ closed: data.isClosed }">
            <div class="node-heading">
              <span class="node-kind">Backend</span>
              <span class="status-badge"
                ><i aria-hidden="true"></i>{{ data.isClosed ? '已断开' : '运行中' }}</span
              >
            </div>
            <div class="node-id">{{ data.connectionId }}</div>
            <div class="node-footer">
              <span>后端服务</span>
              <span>{{ data.sessionCount }} 个 Client</span>
            </div>
            <Handle type="source" :position="Position.Right" />
          </article>
        </template>

        <template #node-client="{ data }">
          <article class="flow-node client-node" :class="{ closed: data.isClosed }">
            <Handle type="target" :position="Position.Left" />
            <div class="node-heading">
              <span class="node-kind">Client</span>
              <span class="status-badge"
                ><i aria-hidden="true"></i>{{ data.isClosed ? '已关闭' : '活跃' }}</span
              >
            </div>
            <div class="node-id" :title="data.connectionId">{{ data.connectionId }}</div>
            <div class="node-footer">
              <span>{{ data.sessionCount }} 个会话</span>
              <span v-if="data.isSynthetic">仅 Session 快照</span>
            </div>
            <Handle type="source" :position="Position.Right" />
          </article>
        </template>

        <template #node-session="{ data }">
          <article class="flow-node session-node" :class="{ closed: data.isClosed }">
            <Handle type="target" :position="Position.Left" />
            <div class="node-heading">
              <span class="node-kind">Session</span>
              <span class="session-type">{{ data.type?.toUpperCase() }}</span>
            </div>
            <div class="node-id" :title="data.sessionId">{{ data.sessionId }}</div>
            <div class="purpose-list">
              <span v-if="!data.purposes?.length" class="purpose-tag muted">未标注</span>
              <span v-for="purpose in data.purposes" :key="purpose" class="purpose-tag">
                {{ formatPurpose(purpose) }}
              </span>
            </div>
            <div class="node-footer">
              <span>{{ data.hasShell ? 'Shell 已就绪' : '无 Shell' }}</span>
              <span>{{ data.isClosed ? 'Client 已关闭' : 'Client 活跃' }}</span>
            </div>
          </article>
        </template>
      </VueFlow>

      <div v-if="!loading && !snapshot" class="empty-state">
        <NEmpty description="当前没有运行中的客户端或会话" />
      </div>
    </main>
  </div>
</template>

<style scoped>
.runtime-view {
  color: #172033;
  background: #f4f7fa;
}

.runtime-view.is-dark {
  color: #e5e7eb;
  background: #111827;
}

.runtime-header {
  z-index: 2;
  display: flex;
  min-height: 78px;
  flex: 0 0 auto;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  padding: 14px 20px;
  border-bottom: 1px solid #dbe2ea;
  background: rgba(255, 255, 255, 0.88);
}

.is-dark .runtime-header {
  border-bottom-color: #273244;
  background: rgba(17, 24, 39, 0.92);
}

.secondary-text {
  color: #64748b;
}

.is-dark .secondary-text {
  color: #94a3b8;
}

.stream-state {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: #475569;
}

.stream-state i,
.status-badge i {
  width: 7px;
  height: 7px;
  flex: 0 0 auto;
  border-radius: 50%;
  background: #94a3b8;
}

.stream-state[data-state='connected'] i,
.status-badge i {
  background: #22c55e;
}

.stream-state[data-state='connecting'] i,
.stream-state[data-state='reconnecting'] i {
  background: #eab308;
  animation: status-pulse 1.4s ease-in-out infinite;
}

.runtime-metric {
  display: grid;
  grid-template-columns: auto auto;
  align-items: baseline;
  gap: 7px;
  color: #64748b;
  font-size: 12px;
}

.runtime-metric strong {
  color: #172033;
  font-size: 22px;
  line-height: 1;
}

.is-dark .runtime-metric {
  color: #94a3b8;
}

.is-dark .runtime-metric strong {
  color: #f8fafc;
}

.runtime-canvas {
  position: relative;
  min-height: 360px;
  flex: 1 1 auto;
}

.runtime-canvas :deep(.vue-flow) {
  background: #f8fafc;
}

.is-dark .runtime-canvas :deep(.vue-flow) {
  background: #151d2a;
}

.flow-node {
  box-sizing: border-box;
  width: 300px;
  height: 124px;
  padding: 13px 15px;
  overflow: hidden;
  border: 1px solid #d7dee8;
  border-radius: 8px;
  color: #172033;
  background: #ffffff;
  box-shadow: 0 8px 24px rgba(15, 23, 42, 0.08);
}

.client-node {
  width: 276px;
  height: 96px;
  border-left: 4px solid #2563eb;
}

.backend-node {
  width: 250px;
  height: 96px;
  border-left: 4px solid #0f766e;
  background: #f0fdfa;
}

.flow-node.closed {
  border-color: #cbd5e1;
  border-left-color: #94a3b8;
  color: #64748b;
  background: #f8fafc;
}

.is-dark .flow-node {
  border-color: #3a475a;
  color: #e5e7eb;
  background: #202b3b;
  box-shadow: 0 10px 28px rgba(0, 0, 0, 0.22);
}

.is-dark .client-node {
  border-left-color: #60a5fa;
}

.is-dark .backend-node {
  border-left-color: #2dd4bf;
  background: #183536;
}

.is-dark .flow-node.closed {
  border-color: #3a475a;
  border-left-color: #64748b;
  color: #94a3b8;
  background: #1a2432;
}

.node-heading,
.node-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.node-kind {
  color: #475569;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0;
  text-transform: uppercase;
}

.is-dark .node-kind {
  color: #a8b4c5;
}

.status-badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  color: #15803d;
  font-size: 11px;
}

.closed .status-badge {
  color: #64748b;
}

.closed .status-badge i {
  background: #94a3b8;
}

.node-id {
  margin-top: 6px;
  overflow: hidden;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 13px;
  font-weight: 650;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.node-footer {
  margin-top: 6px;
  color: #64748b;
  font-size: 10px;
}

.is-dark .node-footer {
  color: #94a3b8;
}

.session-type {
  color: #64748b;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 10px;
}

.purpose-list {
  display: flex;
  height: 22px;
  align-items: center;
  gap: 5px;
  margin-top: 5px;
  overflow: hidden;
}

.purpose-tag {
  flex: 0 0 auto;
  padding: 2px 6px;
  border-radius: 4px;
  color: #1d4ed8;
  background: #dbeafe;
  font-size: 10px;
  line-height: 18px;
}

.purpose-tag.muted {
  color: #64748b;
  background: #e2e8f0;
}

.is-dark .purpose-tag {
  color: #bfdbfe;
  background: #1e3a5f;
}

.is-dark .purpose-tag.muted {
  color: #cbd5e1;
  background: #334155;
}

.runtime-canvas :deep(.vue-flow__handle) {
  width: 9px;
  height: 9px;
  border: 2px solid #ffffff;
  background: #2563eb;
}

.is-dark .runtime-canvas :deep(.vue-flow__handle) {
  border-color: #202b3b;
  background: #60a5fa;
}

.runtime-canvas :deep(.vue-flow__controls) {
  overflow: hidden;
  border: 1px solid #d7dee8;
  border-radius: 6px;
  box-shadow: 0 6px 18px rgba(15, 23, 42, 0.1);
}

.is-dark .runtime-canvas :deep(.vue-flow__controls) {
  border-color: #3a475a;
}

.is-dark .runtime-canvas :deep(.vue-flow__controls-button) {
  border-bottom-color: #3a475a;
  color: #e5e7eb;
  background: #202b3b;
  fill: currentColor;
}

.empty-state {
  pointer-events: none;
  position: absolute;
  inset: 0;
  z-index: 1;
  display: grid;
  place-items: center;
}

@keyframes status-pulse {
  50% {
    opacity: 0.35;
  }
}

@media (max-width: 720px) {
  .runtime-header {
    min-height: 102px;
    align-items: flex-start;
    padding: 12px 14px;
  }

  .runtime-header h1 {
    font-size: 17px;
  }

  .runtime-header > div:last-child {
    gap: 9px;
  }

  .runtime-metric {
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .runtime-metric strong {
    font-size: 18px;
  }

  .runtime-header .secondary-text {
    display: none;
  }
}
</style>

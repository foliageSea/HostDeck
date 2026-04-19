<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import type { RuntimeClientSummary, RuntimeSessionSummary, RuntimeSnapshot } from '@/api/runtime'
import { useSettingsStore } from '@/stores/settings'

const settingsStore = useSettingsStore()

const loading = ref(false)
const refreshAt = ref<Date | null>(null)
const snapshot = ref<RuntimeSnapshot | null>(null)
const wsStatus = ref<'connecting' | 'connected' | 'reconnecting' | 'disconnected'>('disconnected')
let runtimeWs: WebSocket | null = null
let reconnectTimer: number | null = null
let pingTimer: number | null = null
let isIntentionalClose = false

const clients = computed<RuntimeClientSummary[]>(() => snapshot.value?.clients ?? [])
const sessions = computed<RuntimeSessionSummary[]>(() => snapshot.value?.sessions ?? [])

function stopRuntimeWs() {
  if (reconnectTimer !== null) {
    clearTimeout(reconnectTimer)
    reconnectTimer = null
  }

  if (pingTimer !== null) {
    clearInterval(pingTimer)
    pingTimer = null
  }

  if (runtimeWs) {
    runtimeWs.close(1000, 'Normal Closure')
    runtimeWs = null
  }
}

function handleSnapshot(payload: unknown) {
  if (!payload || typeof payload !== 'object') {
    return
  }

  const message = payload as { code?: number; data?: RuntimeSnapshot }
  if (message.code === 200 && message.data) {
    snapshot.value = message.data
    refreshAt.value = new Date()
    loading.value = false
  }
}

function startRuntimeWs() {
  stopRuntimeWs()
  loading.value = true
  wsStatus.value = wsStatus.value === 'disconnected' ? 'connecting' : 'reconnecting'

  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  const wsUrl = `${protocol}//${window.location.host}/api/ws/runtime`
  runtimeWs = new WebSocket(wsUrl)

  runtimeWs.onopen = () => {
    wsStatus.value = 'connected'
    loading.value = false
  }

  runtimeWs.onmessage = (event) => {
    if (event.data === 'pong') {
      return
    }

    try {
      handleSnapshot(JSON.parse(event.data) as unknown)
    } catch (error) {
      console.error('Failed to parse runtime WS message', error)
    }
  }

  runtimeWs.onclose = () => {
    stopRuntimeWs()
    if (isIntentionalClose) {
      wsStatus.value = 'disconnected'
      return
    }

    wsStatus.value = 'reconnecting'
    reconnectTimer = window.setTimeout(() => {
      startRuntimeWs()
    }, 3000)
  }

  pingTimer = window.setInterval(() => {
    if (runtimeWs?.readyState === WebSocket.OPEN) {
      runtimeWs.send('ping')
    }
  }, 10000)
}

function requestRefresh() {
  if (runtimeWs?.readyState === WebSocket.OPEN) {
    loading.value = true
    runtimeWs.send('refresh')
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

function formatWsStatus(value: typeof wsStatus.value) {
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
  startRuntimeWs()
})

onBeforeUnmount(() => {
  isIntentionalClose = true
  stopRuntimeWs()
  wsStatus.value = 'disconnected'
})
</script>

<template>
  <div class="runtime-view flex h-full flex-col gap-[16px] overflow-auto p-[20px]"
    :class="settingsStore.isDark ? 'bg-[linear-gradient(180deg,rgba(15,23,42,0.14),rgba(15,23,42,0.04))]' : 'bg-[linear-gradient(180deg,rgba(255,255,255,0.68),rgba(226,232,240,0.34))]'">
    <div class="flex items-start justify-between gap-[12px] lt-md:flex-col lt-md:items-stretch">
      <div>
        <div class="text-[24px] font-700">运行态会话</div>
        <div class="mt-[6px] text-[13px]"
          :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">
          查看后端当前持有的 clients 与 sessions 摘要
        </div>
      </div>

      <div class="flex items-center gap-[12px] lt-md:justify-between">
        <span class="text-[12px]"
          :class="settingsStore.isDark ? 'text-[rgba(96,165,250,0.92)]' : 'text-[rgba(37,99,235,0.92)]'">
          {{ formatWsStatus(wsStatus) }}
        </span>
        <span class="text-[12px]"
          :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">
          最近刷新：{{ formatRefreshAt(refreshAt) }}
        </span>
        <NButton secondary :loading="loading" :disabled="wsStatus !== 'connected'" @click="requestRefresh">立即刷新</NButton>
      </div>
    </div>

    <div class="grid grid-cols-[repeat(2,minmax(0,1fr))] gap-[16px] lt-md:grid-cols-1">
      <NCard :bordered="false" class="rounded-[18px]"
        :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.82)]'">
        <div class="text-[13px]"
          :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">
          Clients
        </div>
        <div class="mt-[8px] text-[34px] font-700">{{ snapshot?.totalClients ?? 0 }}</div>
      </NCard>

      <NCard :bordered="false" class="rounded-[18px]"
        :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.82)]'">
        <div class="text-[13px]"
          :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.92)]' : 'text-[rgba(100,116,139,0.92)]'">
          Sessions
        </div>
        <div class="mt-[8px] text-[34px] font-700">{{ snapshot?.totalSessions ?? 0 }}</div>
      </NCard>
    </div>

    <div class="grid flex-1 grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)] gap-[16px] lt-lg:grid-cols-1">
      <NCard title="Clients" :bordered="false" class="rounded-[18px] min-h-0"
        :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.82)]'">
        <NDataTable
          :bordered="false"
          :single-line="false"
          :pagination="{ pageSize: 8 }"
          :columns="[
            { title: 'Connection ID', key: 'connectionId' },
            { title: '状态', key: 'isClosed', render: (row: RuntimeClientSummary) => row.isClosed ? '已关闭' : '活跃' },
            { title: '关联 Session', key: 'sessionCount' },
          ]"
          :data="clients"
          :loading="loading"
        />
      </NCard>

      <NCard title="Sessions" :bordered="false" class="rounded-[18px] min-h-0"
        :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.82)]'">
        <NDataTable
          :bordered="false"
          :single-line="false"
          :pagination="{ pageSize: 10 }"
          :columns="[
            { title: 'Session ID', key: 'sessionId' },
            { title: 'Connection ID', key: 'connectionId' },
            { title: '类型', key: 'type' },
            { title: 'Shell', key: 'hasShell', render: (row: RuntimeSessionSummary) => row.hasShell ? '是' : '否' },
            { title: 'Client 状态', key: 'clientClosed', render: (row: RuntimeSessionSummary) => row.clientClosed ? '已关闭' : '活跃' },
          ]"
          :data="sessions"
          :loading="loading"
        />
      </NCard>
    </div>
  </div>
</template>

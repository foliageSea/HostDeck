import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import type { ConnectionStatus, ConnectionStatusResponse, ConnectParams } from '@/api/auth'
import { authApi } from '@/api/auth'
import type { MonitorResponse } from '@/api/system'
import { serverApi, type SavedServer } from '@/api/server'
import { getUiApi } from '@/lib/ui'

export { type SavedServer }

type SessionStatus = ConnectionStatus

export const useSshStore = defineStore('ssh', () => {
  const connectionId = ref<string | null>(null)
  const isConnected = ref(false)
  const isReady = ref(false)
  const sessionStatus = ref<SessionStatus>('disconnected')
  const host = ref('')
  const port = ref<number | null>(null)
  const username = ref('')
  const savedServers = ref<SavedServer[]>([])
  const monitorData = ref<MonitorResponse | null>(null)
  const connectPayload = ref<ConnectParams | null>(null)
  const lastError = ref<string | null>(null)

  let monitorWs: WebSocket | null = null
  let monitorReconnectTimer: number | null = null
  let sessionWs: WebSocket | null = null
  let sessionReconnectTimer: number | null = null
  let sessionPingTimer: number | null = null
  let isIntentionalClose = false

  function stopMonitorWs() {
    if (monitorReconnectTimer) {
      clearTimeout(monitorReconnectTimer)
      monitorReconnectTimer = null
    }

    const ws = monitorWs
    if (ws) {
      ws.onmessage = null
      ws.onclose = null
      ws.onerror = null
      ws.close(1000, 'Normal Closure')
      monitorWs = null
    }

    monitorData.value = null
  }

  function stopSessionWs() {
    if (sessionReconnectTimer) {
      clearTimeout(sessionReconnectTimer)
      sessionReconnectTimer = null
    }

    if (sessionPingTimer) {
      clearInterval(sessionPingTimer)
      sessionPingTimer = null
    }

    const ws = sessionWs
    if (ws) {
      ws.onopen = null
      ws.onmessage = null
      ws.onclose = null
      ws.onerror = null
      ws.close(1000, 'Normal Closure')
      sessionWs = null
    }
  }

  function resetSessionState() {
    connectionId.value = null
    isConnected.value = false
    sessionStatus.value = 'disconnected'
    host.value = ''
    port.value = null
    username.value = ''
    connectPayload.value = null
    lastError.value = null
    monitorData.value = null
  }

  function applyConnectionSnapshot(snapshot: ConnectionStatusResponse, payload?: ConnectParams | null) {
    if (!snapshot) {
      resetSessionState()
      return
    }

    connectionId.value = snapshot.connectionId
    host.value = snapshot.host
    port.value = snapshot.port
    username.value = snapshot.username
    sessionStatus.value = snapshot.status
    isConnected.value = snapshot.isConnected
    lastError.value = snapshot.lastError
    connectPayload.value = payload ?? {
      host: snapshot.host,
      port: snapshot.port,
      username: snapshot.username,
    }
  }

  async function clearSession(options?: { silent?: boolean }) {
    isIntentionalClose = true
    stopSessionWs()
    stopMonitorWs()
    resetSessionState()

    try {
      await authApi.disconnect()
    } catch (error) {
      console.error('Failed to disconnect SSH session', error)
      if (!options?.silent) {
        getUiApi().message.error(error instanceof Error ? error.message : '断开 SSH 会话失败。')
      }
    }
  }

  function handleSessionLost(message = 'SSH 会话已断开，请重新登录。') {
    if (!connectionId.value) {
      return
    }

    stopSessionWs()
    stopMonitorWs()
    resetSessionState()
    getUiApi().message.error(message)
  }

  function startSessionWs() {
    stopSessionWs()
    if (!connectionId.value) {
      return
    }

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/api/ws/session?connectionId=${connectionId.value}`

    const ws = new WebSocket(wsUrl)
    sessionWs = ws

    ws.onmessage = (event) => {
      if (sessionWs !== ws) {
        return
      }

      if (event.data === 'pong') {
        return
      }

      try {
        const payload = JSON.parse(event.data) as ({ type?: string } & NonNullable<ConnectionStatusResponse>)
        if (payload.type !== 'status') {
          return
        }

        applyConnectionSnapshot({
          connectionId: payload.connectionId,
          host: payload.host,
          port: payload.port,
          username: payload.username,
          status: payload.status,
          isConnected: payload.isConnected,
          isRecoverable: payload.isRecoverable,
          lastError: payload.lastError,
          updatedAt: payload.updatedAt,
        }, connectPayload.value)

        if (payload.status === 'disconnected' || payload.status === 'failed') {
          handleSessionLost(payload.lastError || 'SSH 会话已断开，请重新登录。')
        }
      } catch (error) {
        console.error('Failed to parse session WS message', error)
      }
    }

    ws.onclose = (event) => {
      if (sessionWs !== ws) {
        return
      }

      sessionWs = null
      if (sessionPingTimer) {
        clearInterval(sessionPingTimer)
        sessionPingTimer = null
      }

      if (isIntentionalClose || !connectionId.value) {
        return
      }

      if (event.code === 4004) {
        handleSessionLost('SSH 会话不存在，请重新登录。')
        return
      }

      sessionReconnectTimer = window.setTimeout(() => {
        sessionReconnectTimer = null
        startSessionWs()
      }, 3000)
    }

    sessionPingTimer = window.setInterval(() => {
      if (sessionWs === ws && ws.readyState === WebSocket.OPEN) {
        ws.send('ping')
      }
    }, 10000)
  }

  function startMonitorWs() {
    stopMonitorWs()
    if (!connectionId.value) {
      return
    }

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/api/ws/monitor?connectionId=${connectionId.value}`

    const ws = new WebSocket(wsUrl)
    monitorWs = ws
    ws.onmessage = (event) => {
      if (monitorWs !== ws) {
        return
      }

      try {
        const payload = JSON.parse(event.data) as { code?: number; data?: MonitorResponse }
        if (payload.code === 200 && payload.data) {
          monitorData.value = payload.data
        }
      } catch (error) {
        console.error('Failed to parse monitor WS message', error)
      }
    }

    ws.onclose = () => {
      if (monitorWs !== ws) {
        return
      }

      monitorWs = null
      if (isIntentionalClose || !connectionId.value) {
        return
      }

      monitorReconnectTimer = window.setTimeout(() => {
        monitorReconnectTimer = null
        startMonitorWs()
      }, 3000)
    }
  }

  function syncRealtimeChannels() {
    if (!connectionId.value) {
      stopSessionWs()
      stopMonitorWs()
      return
    }

    isIntentionalClose = false
    startSessionWs()
    startMonitorWs()
  }

  async function restoreSession() {
    try {
      const snapshot = await authApi.status()
      applyConnectionSnapshot(snapshot)
      syncRealtimeChannels()
    } catch (error) {
      console.error('Failed to restore SSH session', error)
      resetSessionState()
    } finally {
      isReady.value = true
    }
  }

  async function connect(payload: ConnectParams) {
    isIntentionalClose = false
    sessionStatus.value = 'connecting'
    lastError.value = null

    const snapshot = await authApi.connect(payload)
    applyConnectionSnapshot(snapshot, payload)
    syncRealtimeChannels()
    return snapshot
  }

  async function fetchServers() {
    try {
      savedServers.value = await serverApi.list()
    } catch (error) {
      console.error('Failed to fetch servers', error)
      getUiApi().message.error('加载服务器列表失败。')
    }
  }

  async function addServer(server: Omit<SavedServer, 'id'>) {
    const nextServer = await serverApi.create(server)
    savedServers.value.unshift(nextServer)
    return nextServer
  }

  async function removeServer(id: number) {
    await serverApi.delete(id)
    savedServers.value = savedServers.value.filter((server) => server.id !== id)
  }

  async function updateServer(id: number, payload: Partial<SavedServer>) {
    await serverApi.update(id, payload)
    const targetIndex = savedServers.value.findIndex((server) => server.id === id)

    if (targetIndex !== -1) {
      savedServers.value[targetIndex] = {
        ...savedServers.value[targetIndex],
        ...payload,
      }
    }
  }

  const baseConnectPayload = computed(() => connectPayload.value)

  return {
    addServer,
    clearSession,
    connect,
    connectionId,
    fetchServers,
    baseConnectPayload,
    host,
    isConnected,
    isReady,
    lastError,
    monitorData,
    port,
    removeServer,
    restoreSession,
    savedServers,
    sessionStatus,
    updateServer,
    username,
  }
})

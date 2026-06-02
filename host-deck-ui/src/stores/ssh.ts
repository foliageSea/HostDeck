import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import type { MonitorResponse } from '@/api/system'
import { authApi, type ConnectParams } from '@/api/auth'
import { serverApi, type SavedServer } from '@/api/server'
import { getUiApi } from '@/lib/ui'

export { type SavedServer }

type SessionStatus = 'disconnected' | 'connecting' | 'connected' | 'reconnecting'

export const useSshStore = defineStore('ssh', () => {
  const connectionId = ref<string | null>(null)
  const isConnected = ref(false)
  const sessionStatus = ref<SessionStatus>('disconnected')
  const host = ref('')
  const port = ref<number | null>(null)
  const username = ref('')
  const savedServers = ref<SavedServer[]>([])
  const monitorData = ref<MonitorResponse | null>(null)
  const monitorError = ref<string | null>(null)
  const connectPayload = ref<ConnectParams | null>(null)

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
    monitorError.value = null
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

  async function clearSession() {
    const currentConnectionId = connectionId.value

    isIntentionalClose = true
    stopSessionWs()
    stopMonitorWs()
    connectionId.value = null
    isConnected.value = false
    sessionStatus.value = 'disconnected'
    host.value = ''
    port.value = null
    username.value = ''
    connectPayload.value = null

    if (!currentConnectionId) {
      return
    }

    try {
      await authApi.disconnect(currentConnectionId)
    } catch (error) {
      console.error('Failed to disconnect SSH session', error)
    }
  }

  function handleSessionLost() {
    if (!isConnected.value) {
      return
    }

    getUiApi().message.error('SSH 会话已断开，请重新登录。')
    void clearSession()
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
    ws.onopen = () => {
      if (sessionWs !== ws) {
        return
      }

      sessionStatus.value = 'connected'
    }

    ws.onmessage = (event) => {
      if (sessionWs !== ws) {
        return
      }

      if (event.data === 'pong') {
        return
      }

      try {
        const payload = JSON.parse(event.data) as { status?: string }
        if (payload.status === 'disconnected') {
          handleSessionLost()
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

      if (isIntentionalClose || !isConnected.value) {
        return
      }

      if (event.code === 4004 || event.code === 1011) {
        handleSessionLost()
        return
      }

      sessionStatus.value = 'reconnecting'
      sessionReconnectTimer = window.setTimeout(() => {
        sessionReconnectTimer = null
        sessionStatus.value = 'connecting'
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
        const payload = JSON.parse(event.data) as { code?: number; data?: MonitorResponse; message?: string }
        if (payload.code === 200 && payload.data) {
          monitorError.value = null
          monitorData.value = payload.data
          return
        }

        if (payload.code && payload.code !== 200) {
          monitorData.value = null
          monitorError.value = payload.message || '监控数据推送失败。'
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
      if (isIntentionalClose || !isConnected.value) {
        return
      }

      monitorReconnectTimer = window.setTimeout(() => {
        monitorReconnectTimer = null
        startMonitorWs()
      }, 3000)
    }
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

  function setSession(nextConnectionId: string, nextHost: string, nextPort: number, nextUsername: string, payload?: ConnectParams) {
    connectionId.value = nextConnectionId
    host.value = nextHost
    port.value = nextPort
    username.value = nextUsername
    isConnected.value = true
    isIntentionalClose = false
    sessionStatus.value = 'connecting'
    connectPayload.value = payload ?? {
      host: nextHost,
      port: nextPort,
      username: nextUsername,
    }
    startSessionWs()
    startMonitorWs()
  }

  const baseConnectPayload = computed(() => connectPayload.value)

  return {
    addServer,
    clearSession,
    connectionId,
    fetchServers,
    baseConnectPayload,
    host,
    isConnected,
    monitorData,
    monitorError,
    port,
    removeServer,
    savedServers,
    sessionStatus,
    setSession,
    updateServer,
    username,
  }
})

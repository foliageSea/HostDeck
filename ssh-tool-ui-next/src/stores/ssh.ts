import { ref } from 'vue'
import { defineStore } from 'pinia'
import type { MonitorResponse } from '@/api/system'
import { serverApi, type SavedServer } from '@/api/server'
import { getUiApi } from '@/lib/ui'

export { type SavedServer }

export const useSshStore = defineStore('ssh', () => {
  const sessionId = ref<string | null>(null)
  const connectionId = ref<string | null>(null)
  const isConnected = ref(false)
  const host = ref('')
  const username = ref('')
  const savedServers = ref<SavedServer[]>([])
  const monitorData = ref<MonitorResponse | null>(null)

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

    if (monitorWs) {
      monitorWs.close(1000, 'Normal Closure')
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

    if (sessionWs) {
      sessionWs.close(1000, 'Normal Closure')
      sessionWs = null
    }
  }

  function clearSession() {
    isIntentionalClose = true
    stopSessionWs()
    stopMonitorWs()
    sessionId.value = null
    connectionId.value = null
    isConnected.value = false
    host.value = ''
    username.value = ''
  }

  function handleSessionLost() {
    if (!isConnected.value) {
      return
    }

    getUiApi().message.error('SSH 会话已断开，请重新登录。')
    clearSession()
  }

  function startSessionWs() {
    stopSessionWs()
    if (!sessionId.value) {
      return
    }

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/api/ws/session?sessionId=${sessionId.value}`

    sessionWs = new WebSocket(wsUrl)
    sessionWs.onmessage = (event) => {
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

    sessionWs.onclose = (event) => {
      if (isIntentionalClose || !isConnected.value) {
        return
      }

      if (event.code === 4004 || event.code === 1011) {
        handleSessionLost()
        return
      }

      sessionReconnectTimer = window.setTimeout(() => {
        startSessionWs()
      }, 3000)
    }

    sessionPingTimer = window.setInterval(() => {
      if (sessionWs?.readyState === WebSocket.OPEN) {
        sessionWs.send('ping')
      }
    }, 10000)
  }

  function startMonitorWs() {
    stopMonitorWs()
    if (!sessionId.value) {
      return
    }

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/api/ws/monitor?sessionId=${sessionId.value}`

    monitorWs = new WebSocket(wsUrl)
    monitorWs.onmessage = (event) => {
      try {
        const payload = JSON.parse(event.data) as { code?: number; data?: MonitorResponse }
        if (payload.code === 200 && payload.data) {
          monitorData.value = payload.data
        }
      } catch (error) {
        console.error('Failed to parse monitor WS message', error)
      }
    }

    monitorWs.onclose = () => {
      if (isIntentionalClose || !isConnected.value) {
        return
      }

      monitorReconnectTimer = window.setTimeout(() => {
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

  function setSession(nextSessionId: string, nextConnectionId: string, nextHost: string, nextUsername: string) {
    sessionId.value = nextSessionId
    connectionId.value = nextConnectionId
    host.value = nextHost
    username.value = nextUsername
    isConnected.value = true
    isIntentionalClose = false
    startSessionWs()
    startMonitorWs()
  }

  return {
    addServer,
    clearSession,
    connectionId,
    fetchServers,
    host,
    isConnected,
    monitorData,
    removeServer,
    savedServers,
    sessionId,
    setSession,
    updateServer,
    username,
  }
})

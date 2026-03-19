import { defineStore } from 'pinia'
import { ref } from 'vue'
import { serverApi, type SavedServer } from '@/api/server'
import { type MonitorResponse } from '@/api/system'
import { toast } from '@/components/ui/toast/use-toast'

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
  let wsReconnectTimer: number | null = null

  let sessionWs: WebSocket | null = null
  let sessionWsReconnectTimer: number | null = null
  let sessionWsPingInterval: number | null = null

  let isIntentionalClose = false

  function handleSessionLost() {
    if (isConnected.value) {
      toast({
        title: '会话已断开',
        description: 'SSH会话已失效，请重新登录。',
        variant: 'destructive',
      })
      clearSession()
    }
  }

  function startSessionWs() {
    stopSessionWs()
    if (!sessionId.value) return

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/api/ws/session?sessionId=${sessionId.value}`

    sessionWs = new WebSocket(wsUrl)

    sessionWs.onmessage = (event) => {
      if (event.data === 'pong') return
      try {
        const res = JSON.parse(event.data)
        if (res.status === 'disconnected') {
          handleSessionLost()
        }
      } catch (e) {
        console.error('Failed to parse session WS message', e)
      }
    }

    sessionWs.onclose = (event) => {
      if (isIntentionalClose) return
      if (isConnected.value) {
        if (event.code === 4004 || event.code === 1011) {
          handleSessionLost()
        } else {
          sessionWsReconnectTimer = window.setTimeout(() => {
            startSessionWs()
          }, 3000)
        }
      }
    }

    sessionWsPingInterval = window.setInterval(() => {
      if (sessionWs?.readyState === WebSocket.OPEN) {
        sessionWs.send('ping')
      }
    }, 10000)
  }

  function stopSessionWs() {
    if (sessionWsReconnectTimer) {
      clearTimeout(sessionWsReconnectTimer)
      sessionWsReconnectTimer = null
    }
    if (sessionWsPingInterval) {
      clearInterval(sessionWsPingInterval)
      sessionWsPingInterval = null
    }
    if (sessionWs) {
      sessionWs.close(1000, 'Normal Closure')
      sessionWs = null
    }
  }

  function startMonitorWs() {
    stopMonitorWs()
    if (!sessionId.value) return

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/api/ws/monitor?sessionId=${sessionId.value}`

    monitorWs = new WebSocket(wsUrl)

    monitorWs.onmessage = (event) => {
      try {
        const res = JSON.parse(event.data)
        if (res.code === 200) {
          monitorData.value = res.data
        }
      } catch (e) {
        console.error('Failed to parse monitor WS message', e)
      }
    }

    monitorWs.onclose = () => {
      if (isIntentionalClose) return

      if (isConnected.value) {
        wsReconnectTimer = window.setTimeout(() => {
          startMonitorWs()
        }, 3000)
      }
    }
  }

  function stopMonitorWs() {
    isIntentionalClose = true
    if (wsReconnectTimer) {
      clearTimeout(wsReconnectTimer)
      wsReconnectTimer = null
    }
    if (monitorWs) {
      monitorWs.close(1000, 'Normal Closure')
      monitorWs = null
    }
    monitorData.value = null
  }

  async function fetchServers() {
    try {
      const servers = await serverApi.list()
      savedServers.value = servers
    } catch (e) {
      console.error('Failed to fetch servers:', e)
    }
  }

  function setSession(id: string, connId: string, h: string, u: string) {
    sessionId.value = id
    connectionId.value = connId
    host.value = h
    username.value = u
    isConnected.value = true
    isIntentionalClose = false
    startSessionWs()
    startMonitorWs()
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

  async function addServer(server: Omit<SavedServer, 'id'>) {
    try {
      const newServer = await serverApi.create(server)
      savedServers.value.unshift(newServer)
    } catch (e) {
      console.error('Failed to add server:', e)
      throw e
    }
  }

  async function removeServer(id: number) {
    try {
      await serverApi.delete(id)
      savedServers.value = savedServers.value.filter(s => s.id !== id)
    } catch (e) {
      console.error('Failed to remove server:', e)
      throw e
    }
  }

  async function updateServer(id: number, server: Partial<SavedServer>) {
    try {
      await serverApi.update(id, server)
      const index = savedServers.value.findIndex(s => s.id === id)
      if (index !== -1) {
        savedServers.value[index] = { ...savedServers.value[index], ...server } as SavedServer;
      }
    } catch (e) {
      console.error('Failed to update server:', e)
      throw e
    }
  }

  return {
    sessionId,
    connectionId,
    isConnected,
    host,
    username,
    monitorData,
    setSession,
    clearSession,
    savedServers,
    fetchServers,
    addServer,
    removeServer,
    updateServer
  }
})

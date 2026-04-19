import { computed, reactive } from 'vue'
import { defineStore } from 'pinia'
import type { MonitorResponse } from '@/api/system'
import { authApi, type ConnectParams } from '@/api/auth'
import { getUiApi } from '@/lib/ui'

type SessionStatus = 'disconnected' | 'connecting' | 'connected' | 'reconnecting'

interface WindowConnectionState {
  connectionId: string | null
  isConnected: boolean
  sessionStatus: SessionStatus
  monitorData: MonitorResponse | null
  host: string
  port: number | null
  username: string
}

interface WindowConnectionRuntime {
  isIntentionalClose: boolean
  monitorReconnectTimer: number | null
  monitorWs: WebSocket | null
  sessionPingTimer: number | null
  sessionReconnectTimer: number | null
  sessionWs: WebSocket | null
}

function createEmptyState(): WindowConnectionState {
  return {
    connectionId: null,
    host: '',
    isConnected: false,
    monitorData: null,
    port: null,
    sessionStatus: 'disconnected',
    username: '',
  }
}

function createRuntime(): WindowConnectionRuntime {
  return {
    isIntentionalClose: false,
    monitorReconnectTimer: null,
    monitorWs: null,
    sessionPingTimer: null,
    sessionReconnectTimer: null,
    sessionWs: null,
  }
}

export const useWindowSessionStore = defineStore('windowSession', () => {
  const states = reactive<Record<string, WindowConnectionState>>({})
  const runtimes = new Map<string, WindowConnectionRuntime>()
  const connectPayloads = reactive<Record<string, ConnectParams>>({})

  function ensureState(windowId: string) {
    if (!states[windowId]) {
      states[windowId] = createEmptyState()
    }

    return states[windowId]
  }

  function ensureRuntime(windowId: string) {
    const existingRuntime = runtimes.get(windowId)
    if (existingRuntime) {
      return existingRuntime
    }

    const nextRuntime = createRuntime()
    runtimes.set(windowId, nextRuntime)
    return nextRuntime
  }

  function stopMonitorWs(windowId: string) {
    const runtime = ensureRuntime(windowId)
    const state = ensureState(windowId)

    if (runtime.monitorReconnectTimer) {
      clearTimeout(runtime.monitorReconnectTimer)
      runtime.monitorReconnectTimer = null
    }

    if (runtime.monitorWs) {
      runtime.monitorWs.close(1000, 'Normal Closure')
      runtime.monitorWs = null
    }

    state.monitorData = null
  }

  function stopSessionWs(windowId: string) {
    const runtime = ensureRuntime(windowId)

    if (runtime.sessionReconnectTimer) {
      clearTimeout(runtime.sessionReconnectTimer)
      runtime.sessionReconnectTimer = null
    }

    if (runtime.sessionPingTimer) {
      clearInterval(runtime.sessionPingTimer)
      runtime.sessionPingTimer = null
    }

    if (runtime.sessionWs) {
      runtime.sessionWs.close(1000, 'Normal Closure')
      runtime.sessionWs = null
    }
  }

  async function disconnectWindow(windowId: string) {
    const state = ensureState(windowId)
    const runtime = ensureRuntime(windowId)
    const currentConnectionId = state.connectionId

    runtime.isIntentionalClose = true
    stopSessionWs(windowId)
    stopMonitorWs(windowId)

    state.connectionId = null
    state.host = ''
    state.isConnected = false
    state.port = null
    state.sessionStatus = 'disconnected'
    state.username = ''

    delete connectPayloads[windowId]

    if (!currentConnectionId) {
      return
    }

    try {
      await authApi.disconnect(currentConnectionId)
    } catch (error) {
      console.error('Failed to disconnect window SSH session', error)
    }
  }

  async function handleSessionLost(windowId: string) {
    const state = ensureState(windowId)
    if (!state.isConnected) {
      return
    }

    getUiApi().message.error('窗口 SSH 会话已断开，请重新打开窗口。')
    await disconnectWindow(windowId)
  }

  function startSessionWs(windowId: string) {
    const state = ensureState(windowId)
    const runtime = ensureRuntime(windowId)

    stopSessionWs(windowId)
    if (!state.connectionId) {
      return
    }

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/api/ws/session?connectionId=${state.connectionId}`

    runtime.sessionWs = new WebSocket(wsUrl)
    runtime.sessionWs.onopen = () => {
      state.sessionStatus = 'connected'
    }

    runtime.sessionWs.onmessage = (event) => {
      if (event.data === 'pong') {
        return
      }

      try {
        const payload = JSON.parse(event.data) as { status?: string }
        if (payload.status === 'disconnected') {
          void handleSessionLost(windowId)
        }
      } catch (error) {
        console.error('Failed to parse window session WS message', error)
      }
    }

    runtime.sessionWs.onclose = (event) => {
      if (runtime.isIntentionalClose || !state.isConnected) {
        return
      }

      if (event.code === 4004 || event.code === 1011) {
        void handleSessionLost(windowId)
        return
      }

      state.sessionStatus = 'reconnecting'
      runtime.sessionReconnectTimer = window.setTimeout(() => {
        state.sessionStatus = 'connecting'
        startSessionWs(windowId)
      }, 3000)
    }

    runtime.sessionPingTimer = window.setInterval(() => {
      if (runtime.sessionWs?.readyState === WebSocket.OPEN) {
        runtime.sessionWs.send('ping')
      }
    }, 10000)
  }

  function startMonitorWs(windowId: string) {
    const state = ensureState(windowId)
    const runtime = ensureRuntime(windowId)

    stopMonitorWs(windowId)
    if (!state.connectionId) {
      return
    }

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/api/ws/monitor?connectionId=${state.connectionId}`

    runtime.monitorWs = new WebSocket(wsUrl)
    runtime.monitorWs.onmessage = (event) => {
      try {
        const payload = JSON.parse(event.data) as { code?: number; data?: MonitorResponse }
        if (payload.code === 200 && payload.data) {
          state.monitorData = payload.data
        }
      } catch (error) {
        console.error('Failed to parse window monitor WS message', error)
      }
    }

    runtime.monitorWs.onclose = () => {
      if (runtime.isIntentionalClose || !state.isConnected) {
        return
      }

      runtime.monitorReconnectTimer = window.setTimeout(() => {
        startMonitorWs(windowId)
      }, 3000)
    }
  }

  async function connectWindow(windowId: string, payload: ConnectParams) {
    const state = ensureState(windowId)
    const runtime = ensureRuntime(windowId)

    runtime.isIntentionalClose = false
    state.sessionStatus = 'connecting'
    connectPayloads[windowId] = { ...payload }

    const response = await authApi.connect(payload)
    state.connectionId = response.connectionId
    state.host = payload.host
    state.isConnected = true
    state.port = payload.port
    state.username = payload.username

    startSessionWs(windowId)
    startMonitorWs(windowId)
    return response.connectionId
  }

  async function ensureWindowConnection(windowId: string, payload: ConnectParams) {
    const state = ensureState(windowId)
    if (state.connectionId && state.isConnected) {
      return state.connectionId
    }

    return connectWindow(windowId, payload)
  }

  function getWindowState(windowId: string) {
    return computed(() => ensureState(windowId))
  }

  function hasWindowConnection(windowId: string) {
    const state = states[windowId]
    return Boolean(state?.connectionId && state.isConnected)
  }

  return {
    connectWindow,
    disconnectWindow,
    ensureWindowConnection,
    getWindowState,
    hasWindowConnection,
    states,
  }
})

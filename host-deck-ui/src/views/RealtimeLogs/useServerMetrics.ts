import { onBeforeUnmount, onMounted, ref } from 'vue'
import type { ServerMetricsSnapshot } from '@/api/server-metrics'

export type ServerMetricsConnectionStatus = 'connecting' | 'connected' | 'reconnecting' | 'stopped'

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value)
}

function parseSnapshot(payload: unknown): ServerMetricsSnapshot | null {
  if (!payload || typeof payload !== 'object') return null
  const message = payload as { code?: unknown; data?: unknown }
  if (message.code !== 200 || !message.data || typeof message.data !== 'object') return null

  const data = message.data as Record<string, unknown>
  if (
    !isFiniteNumber(data.timestamp) ||
    !isFiniteNumber(data.uptimeMs) ||
    !isFiniteNumber(data.rssBytes) ||
    !isFiniteNumber(data.peakRssBytes) ||
    (data.cpuPercent !== null && !isFiniteNumber(data.cpuPercent)) ||
    !isFiniteNumber(data.eventLoopLagMs)
  ) {
    return null
  }

  return {
    timestamp: data.timestamp,
    uptimeMs: data.uptimeMs,
    rssBytes: data.rssBytes,
    peakRssBytes: data.peakRssBytes,
    cpuPercent: data.cpuPercent,
    eventLoopLagMs: data.eventLoopLagMs,
  }
}

export function useServerMetrics() {
  const snapshot = ref<ServerMetricsSnapshot | null>(null)
  const connectionStatus = ref<ServerMetricsConnectionStatus>('connecting')

  let socket: WebSocket | null = null
  let reconnectTimer: ReturnType<typeof setTimeout> | undefined
  let pingTimer: ReturnType<typeof setInterval> | undefined
  let generation = 0
  let stopped = false

  function clearTimers() {
    if (reconnectTimer) clearTimeout(reconnectTimer)
    if (pingTimer) clearInterval(pingTimer)
    reconnectTimer = undefined
    pingTimer = undefined
  }

  function closeSocket() {
    const current = socket
    socket = null
    if (current) {
      current.onopen = null
      current.onmessage = null
      current.onerror = null
      current.onclose = null
      current.close(1000, 'Normal Closure')
    }
  }

  function connect() {
    generation += 1
    const currentGeneration = generation
    clearTimers()
    closeSocket()
    connectionStatus.value = snapshot.value ? 'reconnecting' : 'connecting'

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const current = new WebSocket(`${protocol}//${window.location.host}/api/ws/server-metrics`)
    socket = current

    current.onopen = () => {
      if (currentGeneration !== generation) return
      connectionStatus.value = 'connected'
      pingTimer = setInterval(() => {
        if (current.readyState === WebSocket.OPEN) current.send('ping')
      }, 10000)
    }
    current.onmessage = (event) => {
      if (currentGeneration !== generation || event.data === 'pong') return
      try {
        const nextSnapshot = parseSnapshot(JSON.parse(String(event.data)) as unknown)
        if (nextSnapshot) snapshot.value = nextSnapshot
      } catch {
        // Ignore malformed samples and keep the previous valid snapshot.
      }
    }
    current.onerror = () => current.close()
    current.onclose = () => {
      if (currentGeneration !== generation || stopped) return
      if (pingTimer) clearInterval(pingTimer)
      pingTimer = undefined
      socket = null
      connectionStatus.value = 'reconnecting'
      reconnectTimer = setTimeout(connect, 3000)
    }
  }

  function reconnect() {
    stopped = false
    connect()
  }

  function stop() {
    stopped = true
    generation += 1
    clearTimers()
    closeSocket()
    connectionStatus.value = 'stopped'
  }

  onMounted(reconnect)
  onBeforeUnmount(stop)

  return { connectionStatus, reconnect, snapshot, stop }
}

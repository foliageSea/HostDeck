import { onBeforeUnmount, onMounted, ref } from 'vue'
import {
  ServerMetricsStreamHttpError,
  serverMetricsApi,
  type ServerMetricsSnapshot,
} from '@/api/server-metrics'

export type ServerMetricsConnectionStatus =
  | 'connecting'
  | 'connected'
  | 'reconnecting'
  | 'unauthorized'
  | 'stopped'

export function useServerMetrics() {
  const snapshot = ref<ServerMetricsSnapshot | null>(null)
  const connectionStatus = ref<ServerMetricsConnectionStatus>('connecting')

  let controller: AbortController | undefined
  let reconnectTimer: ReturnType<typeof setTimeout> | undefined
  let generation = 0
  let reconnectAttempt = 0
  const reconnectDelaysMs = [1000, 2000, 4000, 8000, 15000]

  function clearReconnectTimer() {
    if (reconnectTimer) clearTimeout(reconnectTimer)
    reconnectTimer = undefined
  }

  function scheduleReconnect(streamGeneration: number) {
    if (streamGeneration !== generation) return
    connectionStatus.value = 'reconnecting'
    const delay =
      reconnectDelaysMs[Math.min(reconnectAttempt, reconnectDelaysMs.length - 1)] ?? 15000
    reconnectAttempt += 1
    reconnectTimer = setTimeout(() => {
      reconnectTimer = undefined
      if (streamGeneration === generation) void openStream(streamGeneration)
    }, delay)
  }

  async function openStream(streamGeneration: number) {
    if (streamGeneration !== generation) return
    controller = new AbortController()
    connectionStatus.value = reconnectAttempt === 0 ? 'connecting' : 'reconnecting'
    try {
      await serverMetricsApi.stream((event) => {
        if (streamGeneration !== generation) return
        if (event.event === 'connected') {
          connectionStatus.value = 'connected'
          reconnectAttempt = 0
        } else {
          snapshot.value = event.data
        }
      }, controller.signal)
    } catch (error) {
      if (streamGeneration !== generation || controller.signal.aborted) return
      if (error instanceof ServerMetricsStreamHttpError && error.status === 401) {
        connectionStatus.value = 'unauthorized'
        return
      }
      scheduleReconnect(streamGeneration)
    }
  }

  function reconnect() {
    generation += 1
    controller?.abort()
    clearReconnectTimer()
    reconnectAttempt = 0
    void openStream(generation)
  }

  function stop() {
    generation += 1
    controller?.abort()
    controller = undefined
    clearReconnectTimer()
    connectionStatus.value = 'stopped'
  }

  onMounted(reconnect)
  onBeforeUnmount(stop)

  return { connectionStatus, reconnect, snapshot, stop }
}

import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import {
  LogStreamHttpError,
  logsApi,
  type RealtimeLogItem,
  type RealtimeLogStreamEvent,
} from '@/api/logs'

const ringLimit = 500
const batchDelayMs = 50
const reconnectDelaysMs = [1000, 2000, 4000, 8000, 15000]

export type RealtimeLogConnectionStatus =
  | 'connecting'
  | 'connected'
  | 'reconnecting'
  | 'unauthorized'
  | 'stopped'

function appendBounded(target: RealtimeLogItem[], items: RealtimeLogItem[]) {
  const overflow = target.length + items.length - ringLimit
  if (overflow > 0) {
    target.splice(0, overflow)
  }
  target.push(...items.slice(-ringLimit))
}

export function useRealtimeLogs() {
  const logs = ref<RealtimeLogItem[]>([])
  const pending = ref<RealtimeLogItem[]>([])
  const paused = ref(false)
  const connectionStatus = ref<RealtimeLogConnectionStatus>('connecting')
  const connectionError = ref('')
  const receivedCount = ref(0)
  const lastEventId = ref<string>()
  const replayTruncated = ref(false)

  let controller: AbortController | undefined
  let generation = 0
  let reconnectAttempt = 0
  let reconnectTimer: ReturnType<typeof setTimeout> | undefined
  let batchTimer: ReturnType<typeof setTimeout> | undefined
  let batch: RealtimeLogItem[] = []
  const seenIds = new Set<string>()
  const seenOrder: string[] = []

  const bufferedCount = computed(() => pending.value.length + batch.length)

  function rememberId(id: string) {
    if (seenIds.has(id)) {
      return false
    }
    seenIds.add(id)
    seenOrder.push(id)
    if (seenOrder.length > ringLimit * 2) {
      const removed = seenOrder.shift()
      if (removed !== undefined) {
        seenIds.delete(removed)
      }
    }
    return true
  }

  function flushBatch() {
    batchTimer = undefined
    if (batch.length === 0) {
      return
    }
    const next = batch
    batch = []
    if (paused.value) {
      const target = [...pending.value]
      appendBounded(target, next)
      pending.value = target
    } else {
      const target = [...logs.value]
      appendBounded(target, next)
      logs.value = target
    }
  }

  function queueLog(item: RealtimeLogItem) {
    if (!rememberId(String(item.id))) {
      return
    }
    receivedCount.value += 1
    batch.push(item)
    if (!batchTimer) {
      batchTimer = setTimeout(flushBatch, batchDelayMs)
    }
  }

  function handleEvent(event: RealtimeLogStreamEvent, streamGeneration: number) {
    if (streamGeneration !== generation) {
      return
    }
    if (event.id !== undefined) {
      lastEventId.value = event.id
    }
    if (event.event === 'connected') {
      connectionStatus.value = 'connected'
      connectionError.value = ''
      replayTruncated.value = event.data.replayTruncated
      reconnectAttempt = 0
    } else if (event.event === 'log') {
      queueLog(event.data)
    } else {
      connectionError.value = event.message
    }
  }

  function scheduleReconnect(streamGeneration: number) {
    if (streamGeneration !== generation) {
      return
    }
    connectionStatus.value = 'reconnecting'
    const delay =
      reconnectDelaysMs[Math.min(reconnectAttempt, reconnectDelaysMs.length - 1)] ?? 15000
    reconnectAttempt += 1
    reconnectTimer = setTimeout(() => {
      reconnectTimer = undefined
      if (streamGeneration === generation) {
        void openStream(streamGeneration)
      }
    }, delay)
  }

  async function openStream(streamGeneration: number) {
    if (streamGeneration !== generation) {
      return
    }
    controller = new AbortController()
    connectionStatus.value = reconnectAttempt === 0 ? 'connecting' : 'reconnecting'
    try {
      await logsApi.stream(
        lastEventId.value,
        (event) => handleEvent(event, streamGeneration),
        controller.signal,
      )
    } catch (error) {
      if (streamGeneration !== generation || controller.signal.aborted) {
        return
      }
      connectionError.value = error instanceof Error ? error.message : '实时日志连接失败。'
      if (error instanceof LogStreamHttpError && error.status === 401) {
        connectionStatus.value = 'unauthorized'
        return
      }
      scheduleReconnect(streamGeneration)
    }
  }

  function reconnect() {
    generation += 1
    controller?.abort()
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = undefined
    }
    reconnectAttempt = 0
    connectionError.value = ''
    void openStream(generation)
  }

  function setPaused(value: boolean) {
    if (paused.value === value) {
      return
    }
    flushBatch()
    paused.value = value
    if (!value && pending.value.length > 0) {
      const target = [...logs.value]
      appendBounded(target, pending.value)
      logs.value = target
      pending.value = []
    }
  }

  function clear() {
    logs.value = []
    pending.value = []
    batch = []
    if (batchTimer) {
      clearTimeout(batchTimer)
      batchTimer = undefined
    }
  }

  function stop() {
    generation += 1
    controller?.abort()
    controller = undefined
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = undefined
    }
    if (batchTimer) {
      clearTimeout(batchTimer)
      batchTimer = undefined
    }
    batch = []
    connectionStatus.value = 'stopped'
  }

  onMounted(reconnect)
  onBeforeUnmount(stop)

  return {
    bufferedCount,
    clear,
    connectionError,
    connectionStatus,
    lastEventId,
    logs,
    paused,
    pending,
    receivedCount,
    reconnect,
    replayTruncated,
    setPaused,
    stop,
  }
}

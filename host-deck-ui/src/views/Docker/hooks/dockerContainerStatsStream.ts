import { dockerApi, type DockerContainerStatsSample } from '@/api/docker'

interface StreamState {
  status: 'connecting' | 'reconnecting' | 'live' | 'ended' | 'error'
  error: string
  sample?: DockerContainerStatsSample
}

type Listener = (state: StreamState) => void

interface StreamEntry {
  state: StreamState
  listeners: Set<Listener>
  controller?: AbortController
  retryTimer?: ReturnType<typeof setTimeout>
  retryAttempt: number
}

const streams = new Map<string, StreamEntry>()
const sampleTimeoutMs = 15_000
const retryDelaysMs = [1000, 2000, 4000, 8000]
const streamKey = (connectionId: string, containerId: string) =>
  JSON.stringify([connectionId, containerId])

function publish(entry: StreamEntry, state: StreamState) {
  entry.state = state
  for (const listener of entry.listeners) listener(state)
}

async function openStream(entry: StreamEntry, connectionId: string, containerId: string) {
  const controller = new AbortController()
  entry.controller = controller
  const { signal } = controller
  let sampleTimer: ReturnType<typeof setTimeout> | undefined

  function reconnect(message: string) {
    const delay = retryDelaysMs[entry.retryAttempt]
    if (delay === undefined) {
      publish(entry, { status: 'error', error: message })
      return
    }
    entry.retryAttempt += 1
    entry.retryTimer = setTimeout(() => {
      entry.retryTimer = undefined
      void openStream(entry, connectionId, containerId)
    }, delay)
    publish(entry, { status: 'reconnecting', error: '' })
  }

  function expectSample() {
    clearTimeout(sampleTimer)
    // Heartbeats alone do not mean stats are available. Fall back if data stalls.
    sampleTimer = setTimeout(() => {
      controller.abort()
      reconnect('获取容器资源监控样本超时。')
    }, sampleTimeoutMs)
  }

  signal.addEventListener('abort', () => clearTimeout(sampleTimer), { once: true })
  expectSample()
  try {
    await dockerApi.streamContainerStats(connectionId, containerId, (event) => {
      if (signal.aborted || entry.state.status === 'ended') return
      if (event.event === 'stats') {
        expectSample()
        entry.retryAttempt = 0
        publish(entry, { status: 'live', error: '', sample: event.data })
      } else if (event.event === 'connected' && entry.state.status !== 'live') {
        publish(entry, { status: 'live', error: '' })
      } else if (event.event === 'done') {
        clearTimeout(sampleTimer)
        publish(entry, { status: 'ended', error: '' })
      }
    }, signal)
    if (!signal.aborted && entry.state.status !== 'ended') {
      reconnect('容器资源监控流意外结束。')
    }
  } catch (error) {
    if (!signal.aborted && entry.state.status !== 'ended') {
      reconnect(error instanceof Error ? error.message : '容器资源监控失败。')
    }
  } finally {
    clearTimeout(sampleTimer)
    if (entry.controller === controller) entry.controller = undefined
  }
}

export function getLiveContainerStats(connectionId: string, containerId: string) {
  const state = streams.get(streamKey(connectionId, containerId))?.state
  return state?.status === 'live' ? state.sample : undefined
}

export function subscribeContainerStats(connectionId: string, containerId: string, listener: Listener) {
  const key = streamKey(connectionId, containerId)
  let entry = streams.get(key)
  if (!entry) {
    entry = { state: { status: 'connecting', error: '' }, listeners: new Set(), retryAttempt: 0 }
    streams.set(key, entry)
  }

  const current = entry
  // Wrap so each subscription owns a separate release, even with the same callback.
  const subscription: Listener = (state) => listener(state)
  current.listeners.add(subscription)
  subscription(current.state)
  if (current.listeners.size === 1) void openStream(current, connectionId, containerId)

  return () => {
    if (!current.listeners.delete(subscription) || current.listeners.size) return
    streams.delete(key)
    clearTimeout(current.retryTimer)
    current.controller?.abort()
  }
}

// A window's manual refresh can retry a terminal stream without disrupting an active one.
export function retryContainerStats(connectionId: string, containerId: string) {
  const entry = streams.get(streamKey(connectionId, containerId))
  if (!entry || (entry.state.status !== 'error' && entry.state.status !== 'ended')) return
  entry.controller?.abort()
  entry.retryAttempt = 0
  publish(entry, { status: 'connecting', error: '' })
  void openStream(entry, connectionId, containerId)
}

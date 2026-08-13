import { handleAccessUnauthorized } from '@/lib/http'
import { consumeServerSentEvents } from '@/lib/sse'

export interface ServerMetricsSnapshot {
  timestamp: number
  uptimeMs: number
  rssBytes: number
  peakRssBytes: number
  cpuPercent: number | null
  eventLoopLagMs: number
}

export type ServerMetricsStreamEvent =
  | { event: 'connected'; retry?: number }
  | { event: 'metrics'; data: ServerMetricsSnapshot; retry?: number }

export class ServerMetricsStreamHttpError extends Error {
  readonly status: number

  constructor(message: string, status: number) {
    super(message)
    this.name = 'ServerMetricsStreamHttpError'
    this.status = status
  }
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value)
}

function parseSnapshot(payload: unknown): ServerMetricsSnapshot | null {
  if (!payload || typeof payload !== 'object') return null
  const data = payload as Record<string, unknown>
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

async function getErrorMessage(response: Response) {
  const body = await response.text()
  try {
    return (JSON.parse(body) as { message?: string }).message || body
  } catch {
    return body
  }
}

export const serverMetricsApi = {
  async stream(
    onEvent: (event: ServerMetricsStreamEvent) => void,
    signal?: AbortSignal,
  ) {
    const response = await fetch('/api/server/metrics/stream', {
      credentials: 'same-origin',
      headers: { Accept: 'text/event-stream' },
      signal,
    })
    if (!response.ok) {
      if (response.status === 401) {
        handleAccessUnauthorized()
      }
      const message =
        (await getErrorMessage(response)) || `连接服务指标失败 (${response.status})`
      throw new ServerMetricsStreamHttpError(message, response.status)
    }
    if (!response.body) {
      throw new Error('浏览器未提供流式响应。')
    }

    await consumeServerSentEvents(response.body, (message) => {
      const metadata = message.retry !== undefined ? { retry: message.retry } : {}
      if (message.event === 'connected') {
        onEvent({ event: 'connected', ...metadata })
        return
      }
      if (message.event === 'metrics') {
        try {
          const snapshot = parseSnapshot(JSON.parse(message.data) as unknown)
          if (snapshot) onEvent({ event: 'metrics', data: snapshot, ...metadata })
        } catch {
          // Ignore malformed samples and keep the previous valid snapshot.
        }
        return
      }
      if (message.event === 'error') {
        let errorMessage = message.data
        try {
          errorMessage = (JSON.parse(message.data) as { message?: string }).message || errorMessage
        } catch {
          // A plain SSE error message is already suitable for display.
        }
        throw new Error(errorMessage)
      }
    })

    if (!signal?.aborted) {
      throw new Error('服务指标连接已结束。')
    }
  },
}

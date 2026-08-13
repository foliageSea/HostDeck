import { handleAccessUnauthorized } from '@/lib/http'
import { consumeServerSentEvents } from '@/lib/sse'

export interface RealtimeLogItem {
  id: number
  timestamp: string
  level: string
  levelValue: number
  logger: string
  message: string
  error?: string
  stackTrace?: string
}

export interface RealtimeLogConnectionInfo {
  cursor: number | null
  requestedCursor: number | null
  oldestId: number | null
  latestId: number | null
  replayTruncated: boolean
}

export type RealtimeLogStreamEvent =
  | { event: 'connected'; data: RealtimeLogConnectionInfo; id?: string; retry?: number }
  | { event: 'log'; data: RealtimeLogItem; id?: string; retry?: number }
  | { event: 'error'; message: string; id?: string; retry?: number }

export class LogStreamHttpError extends Error {
  readonly status: number

  constructor(message: string, status: number) {
    super(message)
    this.status = status
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

export const logsApi = {
  async stream(
    lastEventId: string | undefined,
    onEvent: (event: RealtimeLogStreamEvent) => void,
    signal?: AbortSignal,
  ) {
    const headers: Record<string, string> = { Accept: 'text/event-stream' }
    if (lastEventId) {
      headers['Last-Event-ID'] = lastEventId
    }

    const response = await fetch('/api/logs/stream', {
      credentials: 'same-origin',
      headers,
      signal,
    })
    if (!response.ok) {
      if (response.status === 401) {
        handleAccessUnauthorized()
      }
      const message = (await getErrorMessage(response)) || `连接实时日志失败 (${response.status})`
      throw new LogStreamHttpError(message, response.status)
    }
    if (!response.body) {
      throw new Error('浏览器未提供流式响应。')
    }

    await consumeServerSentEvents(response.body, (message) => {
      const metadata = {
        ...(message.id !== undefined ? { id: message.id } : {}),
        ...(message.retry !== undefined ? { retry: message.retry } : {}),
      }
      if (message.event === 'connected') {
        onEvent({
          event: 'connected',
          data: JSON.parse(message.data) as RealtimeLogConnectionInfo,
          ...metadata,
        })
        return
      }
      if (message.event === 'log') {
        onEvent({
          event: 'log',
          data: JSON.parse(message.data) as RealtimeLogItem,
          ...metadata,
        })
        return
      }
      if (message.event === 'error') {
        let errorMessage = message.data
        try {
          errorMessage = (JSON.parse(message.data) as { message?: string }).message || errorMessage
        } catch {
          // A plain SSE error message is already suitable for display.
        }
        onEvent({ event: 'error', message: errorMessage, ...metadata })
        throw new Error(errorMessage)
      }
    })

    if (!signal?.aborted) {
      throw new Error('实时日志连接已结束。')
    }
  },
}

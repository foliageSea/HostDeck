import { afterEach, describe, expect, it, vi } from 'vitest'
import { logsApi } from '@/api/logs'
import { setAccessUnauthorizedHandler } from '@/lib/http'

describe('logsApi.stream', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    setAccessUnauthorizedHandler(() => undefined)
  })

  it('uses same-origin credentials and resumes from the last SSE id', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(
        new Response(
          'event: connected\ndata: {"cursor":1,"requestedCursor":1,"oldestId":1,"latestId":2,"replayTruncated":false}\n\n' +
            'id: 2\nevent: log\ndata: {"id":2,"timestamp":"2026-08-13T00:00:00.000Z","level":"INFO","levelValue":800,"logger":"server","message":"ready"}\n\n',
          { headers: { 'Content-Type': 'text/event-stream' } },
        ),
      )
    vi.stubGlobal('fetch', fetchMock)
    const events: unknown[] = []

    await expect(logsApi.stream('evt-1', (event) => events.push(event))).rejects.toThrow(
      '实时日志连接已结束。',
    )

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/logs/stream',
      expect.objectContaining({
        credentials: 'same-origin',
        headers: { Accept: 'text/event-stream', 'Last-Event-ID': 'evt-1' },
      }),
    )
    expect(events).toEqual([
      {
        event: 'connected',
        data: {
          cursor: 1,
          requestedCursor: 1,
          oldestId: 1,
          latestId: 2,
          replayTruncated: false,
        },
      },
      {
        event: 'log',
        id: '2',
        data: expect.objectContaining({ id: 2, message: 'ready' }),
      },
    ])
  })

  it('notifies the access layer on an unauthorized response', async () => {
    const unauthorized = vi.fn()
    setAccessUnauthorizedHandler(unauthorized)
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response('{"message":"unauthorized"}', {
          status: 401,
          headers: { 'Content-Type': 'application/json' },
        }),
      ),
    )

    await expect(logsApi.stream(undefined, () => undefined)).rejects.toMatchObject({ status: 401 })
    expect(unauthorized).toHaveBeenCalledOnce()
  })
})

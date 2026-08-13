import { afterEach, describe, expect, it, vi } from 'vitest'
import { serverMetricsApi } from '@/api/server-metrics'
import { setAccessUnauthorizedHandler } from '@/lib/http'

describe('serverMetricsApi.stream', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    setAccessUnauthorizedHandler(() => undefined)
  })

  it('parses valid samples and ignores malformed samples', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        'event: connected\nretry: 3000\ndata: {}\n\n' +
          'event: metrics\ndata: {"timestamp":1000,"uptimeMs":2000,"rssBytes":3000,"peakRssBytes":4000,"cpuPercent":12.5,"eventLoopLagMs":1.25}\n\n' +
          'event: metrics\ndata: {"rssBytes":"invalid"}\n\n',
        { headers: { 'Content-Type': 'text/event-stream' } },
      ),
    )
    vi.stubGlobal('fetch', fetchMock)
    const events: unknown[] = []

    await expect(serverMetricsApi.stream((event) => events.push(event))).rejects.toThrow(
      '服务指标连接已结束。',
    )

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/server/metrics/stream',
      expect.objectContaining({
        credentials: 'same-origin',
        headers: { Accept: 'text/event-stream' },
      }),
    )
    expect(events).toEqual([
      { event: 'connected', retry: 3000 },
      {
        event: 'metrics',
        data: {
          timestamp: 1000,
          uptimeMs: 2000,
          rssBytes: 3000,
          peakRssBytes: 4000,
          cpuPercent: 12.5,
          eventLoopLagMs: 1.25,
        },
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

    await expect(serverMetricsApi.stream(() => undefined)).rejects.toMatchObject({ status: 401 })
    expect(unauthorized).toHaveBeenCalledOnce()
  })
})

import { afterEach, describe, expect, it, vi } from 'vitest'

import {
  dockerApi,
  type DockerContainerLogStreamEvent,
  type DockerContainerStatsStreamEvent,
} from '@/api/docker'
import { http } from '@/lib/http'

function sseResponse(body: string, status = 200) {
  return new Response(body, {
    status,
    headers: { 'Content-Type': status === 200 ? 'text/event-stream' : 'application/json' },
  })
}

describe('dockerApi.streamContainerLogs', () => {
  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  it('fetches the initial container log snapshot', async () => {
    const getMock = vi.spyOn(http, 'get').mockResolvedValue({
      data: { events: [{ stream: 'stdout', text: 'existing\n' }] },
    })

    await expect(
      dockerApi.getContainerLogs('conn-1', 'container-1', { tail: 500, timestamps: true }),
    ).resolves.toEqual({ events: [{ stream: 'stdout', text: 'existing\n' }] })
    expect(getMock).toHaveBeenCalledWith('/api/docker/containers/logs/snapshot', {
      params: {
        connectionId: 'conn-1',
        containerId: 'container-1',
        tail: 500,
        timestamps: true,
      },
    })
  })

  it('streams only subsequent container log events', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(
        sseResponse(
          'event: connected\ndata: {}\n\n' +
            'event: stdout\ndata: {"text":"hello\\n"}\n\n' +
            'event: stderr\ndata: {"text":"error\\n"}\n\n' +
            'event: done\ndata: {}\n\n',
        ),
      )
    vi.stubGlobal('fetch', fetchMock)
    const events: DockerContainerLogStreamEvent[] = []

    await dockerApi.streamContainerLogs(
      'conn-1',
      'container-1',
      { timestamps: true },
      (event) => events.push(event),
    )

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/docker/containers/logs?connectionId=conn-1&containerId=container-1&timestamps=true',
      expect.objectContaining({ credentials: 'same-origin' }),
    )
    expect(events.map((event) => event.event)).toEqual(['connected', 'stdout', 'stderr', 'done'])
  })

  it('reports connected as soon as the streaming response is established', async () => {
    const abortController = new AbortController()
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        abortController.signal.addEventListener('abort', () => controller.close())
      },
    })
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(stream, {
          headers: { 'Content-Type': 'text/event-stream' },
        }),
      ),
    )
    const events: DockerContainerLogStreamEvent[] = []

    const request = dockerApi.streamContainerLogs(
      'conn-1',
      'container-1',
      {},
      (event) => events.push(event),
      abortController.signal,
    )
    await vi.waitFor(() => expect(events.map((event) => event.event)).toEqual(['connected']))
    abortController.abort()
    await expect(request).rejects.toThrow('容器日志流意外结束。')
  })

  it('reports a server error event', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockResolvedValue(
          sseResponse('event: error\ndata: {"message":"container disappeared"}\n\n'),
        ),
    )

    await expect(
      dockerApi.streamContainerLogs('conn-1', 'container-1', {}, () => undefined),
    ).rejects.toThrow('container disappeared')
  })

  it('reports a stream that ends without a done event', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(sseResponse('event: connected\ndata: {}\n\n')))

    await expect(
      dockerApi.streamContainerLogs('conn-1', 'container-1', {}, () => undefined),
    ).rejects.toThrow('容器日志流意外结束。')
  })
})

describe('dockerApi.streamContainerStats', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('streams numeric resource samples', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(
        sseResponse(
          'event: connected\ndata: {}\n\n' +
            'event: stats\ndata: {"id":"container-1","name":"web","timestamp":1,"cpuPercent":2.5,"memoryPercent":10,"memoryUsage":100,"memoryLimit":1000,"networkRxBytes":20,"networkTxBytes":30,"networkRxBytesPerSecond":4,"networkTxBytesPerSecond":5,"blockReadBytes":0,"blockWriteBytes":0,"pids":2}\n\n',
        ),
      )
    vi.stubGlobal('fetch', fetchMock)
    const events: DockerContainerStatsStreamEvent[] = []

    await dockerApi.streamContainerStats('conn-1', 'container/1', (event) => events.push(event))

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/docker/containers/container%2F1/stats/stream?connectionId=conn-1',
      expect.objectContaining({ credentials: 'same-origin' }),
    )
    expect(events.map((event) => event.event)).toEqual(['connected', 'stats'])
    expect(events[1]?.data).toEqual(expect.objectContaining({ cpuPercent: 2.5 }))
  })
})

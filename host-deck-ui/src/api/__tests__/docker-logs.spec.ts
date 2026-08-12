import { afterEach, describe, expect, it, vi } from 'vitest'

import { dockerApi, type DockerContainerLogStreamEvent } from '@/api/docker'

function sseResponse(body: string, status = 200) {
  return new Response(body, {
    status,
    headers: { 'Content-Type': status === 200 ? 'text/event-stream' : 'application/json' },
  })
}

describe('dockerApi.streamContainerLogs', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('streams container log events with the requested options', async () => {
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
      { tail: 500, timestamps: true },
      (event) => events.push(event),
    )

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/docker/containers/logs?connectionId=conn-1&containerId=container-1&tail=500&timestamps=true',
      expect.objectContaining({ credentials: 'same-origin' }),
    )
    expect(events.map((event) => event.event)).toEqual(['connected', 'stdout', 'stderr', 'done'])
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

import { defineComponent, nextTick } from 'vue'
import { mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const { connections, streamMock } = vi.hoisted(() => ({
  connections: [] as Array<{
    onEvent: (event: unknown) => void
    reject: (error: Error) => void
  }>,
  streamMock: vi.fn(),
}))

vi.mock('@/api/server-metrics', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/api/server-metrics')>()
  return { ...actual, serverMetricsApi: { stream: streamMock } }
})

import { useServerMetrics } from '../useServerMetrics'

function mountController() {
  let controller: ReturnType<typeof useServerMetrics> | undefined
  const wrapper = mount(
    defineComponent({
      setup() {
        controller = useServerMetrics()
        return () => null
      },
    }),
  )
  if (!controller) throw new Error('controller was not created')
  return { controller, wrapper }
}

describe('useServerMetrics', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    connections.length = 0
    streamMock.mockReset()
    streamMock.mockImplementation(
      (onEvent: (event: unknown) => void, signal?: AbortSignal) =>
        new Promise<void>((resolve, reject) => {
          connections.push({ onEvent, reject })
          signal?.addEventListener('abort', () => resolve(), { once: true })
        }),
    )
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('connects and accepts metric snapshots', async () => {
    const { controller, wrapper } = mountController()
    await nextTick()

    connections[0]?.onEvent({ event: 'connected' })
    connections[0]?.onEvent({
      event: 'metrics',
      data: {
        timestamp: 1000,
        uptimeMs: 2000,
        rssBytes: 3000,
        peakRssBytes: 4000,
        cpuPercent: 12.5,
        eventLoopLagMs: 1.25,
      },
    })

    expect(controller.connectionStatus.value).toBe('connected')
    expect(controller.snapshot.value?.rssBytes).toBe(3000)
    wrapper.unmount()
  })

  it('reconnects after disconnect and stops after unmount', async () => {
    const { controller, wrapper } = mountController()
    await nextTick()
    connections[0]?.reject(new Error('disconnected'))
    await Promise.resolve()
    expect(controller.connectionStatus.value).toBe('reconnecting')

    await vi.advanceTimersByTimeAsync(1000)
    expect(streamMock).toHaveBeenCalledTimes(2)

    wrapper.unmount()
    await vi.advanceTimersByTimeAsync(15000)
    expect(streamMock).toHaveBeenCalledTimes(2)
    expect(controller.connectionStatus.value).toBe('stopped')
  })
})

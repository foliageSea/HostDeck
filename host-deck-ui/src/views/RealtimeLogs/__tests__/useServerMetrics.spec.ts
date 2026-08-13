import { defineComponent, nextTick } from 'vue'
import { mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useServerMetrics } from '../useServerMetrics'

class MockWebSocket {
  static readonly OPEN = 1
  static instances: MockWebSocket[] = []

  readonly url: string
  readyState = MockWebSocket.OPEN
  onopen: (() => void) | null = null
  onmessage: ((event: MessageEvent) => void) | null = null
  onerror: (() => void) | null = null
  onclose: (() => void) | null = null
  send = vi.fn()
  close = vi.fn(() => {
    this.readyState = 3
  })

  constructor(url: string | URL) {
    this.url = String(url)
    MockWebSocket.instances.push(this)
  }

  open() {
    this.onopen?.()
  }

  message(data: string) {
    this.onmessage?.({ data } as MessageEvent)
  }

  disconnect() {
    this.readyState = 3
    this.onclose?.()
  }
}

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
    MockWebSocket.instances = []
    vi.stubGlobal('WebSocket', MockWebSocket)
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
  })

  it('connects and accepts valid metric snapshots', async () => {
    const { controller, wrapper } = mountController()
    await nextTick()
    const socket = MockWebSocket.instances[0]
    expect(socket?.url).toBe('ws://localhost:3000/api/ws/server-metrics')

    socket?.open()
    socket?.message(
      JSON.stringify({
        code: 200,
        data: {
          timestamp: 1000,
          uptimeMs: 2000,
          rssBytes: 3000,
          peakRssBytes: 4000,
          cpuPercent: 12.5,
          eventLoopLagMs: 1.25,
        },
      }),
    )

    expect(controller.connectionStatus.value).toBe('connected')
    expect(controller.snapshot.value?.rssBytes).toBe(3000)
    socket?.message('{invalid')
    expect(controller.snapshot.value?.rssBytes).toBe(3000)
    wrapper.unmount()
  })

  it('reconnects after disconnect and stops after unmount', async () => {
    const { controller, wrapper } = mountController()
    await nextTick()
    MockWebSocket.instances[0]?.disconnect()
    expect(controller.connectionStatus.value).toBe('reconnecting')

    await vi.advanceTimersByTimeAsync(3000)
    expect(MockWebSocket.instances).toHaveLength(2)

    wrapper.unmount()
    await vi.advanceTimersByTimeAsync(3000)
    expect(MockWebSocket.instances).toHaveLength(2)
    expect(controller.connectionStatus.value).toBe('stopped')
  })
})

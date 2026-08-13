import { defineComponent, nextTick } from 'vue'
import { mount } from '@vue/test-utils'
import { afterEach, describe, expect, it, vi } from 'vitest'

const { stream } = vi.hoisted(() => ({ stream: vi.fn() }))

vi.mock('@/api/logs', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/api/logs')>()
  return { ...original, logsApi: { stream } }
})

import type { RealtimeLogStreamEvent } from '@/api/logs'
import { useRealtimeLogs } from '../useRealtimeLogs'

function log(id: string) {
  const numericId = Number(id)
  return {
    event: 'log' as const,
    id,
    data: {
      id: numericId,
      timestamp: '2026-08-13T00:00:00.000Z',
      level: 'INFO',
      levelValue: 800,
      logger: 'test',
      message: id,
    },
  }
}

function mountController() {
  let controller: ReturnType<typeof useRealtimeLogs> | undefined
  const wrapper = mount(
    defineComponent({
      setup() {
        controller = useRealtimeLogs()
        return () => null
      },
    }),
  )
  if (!controller) throw new Error('controller was not created')
  return { controller, wrapper }
}

describe('useRealtimeLogs', () => {
  afterEach(() => {
    vi.useRealTimers()
    stream.mockReset()
  })

  it('batches, deduplicates and buffers logs while display is paused', async () => {
    vi.useFakeTimers()
    let onEvent: ((event: RealtimeLogStreamEvent) => void) | undefined
    stream.mockImplementation((_lastEventId, callback: (event: RealtimeLogStreamEvent) => void) => {
      onEvent = callback
      return new Promise(() => undefined)
    })
    const { controller, wrapper } = mountController()
    await nextTick()

    onEvent?.(log('1'))
    onEvent?.(log('1'))
    await vi.advanceTimersByTimeAsync(50)
    expect(controller.logs.value.map((item) => item.id)).toEqual([1])
    expect(controller.receivedCount.value).toBe(1)

    controller.setPaused(true)
    onEvent?.(log('2'))
    await vi.advanceTimersByTimeAsync(50)
    expect(controller.logs.value.map((item) => item.id)).toEqual([1])
    expect(controller.pending.value.map((item) => item.id)).toEqual([2])

    controller.setPaused(false)
    expect(controller.logs.value.map((item) => item.id)).toEqual([1, 2])
    expect(controller.pending.value).toEqual([])
    wrapper.unmount()
  })

  it('ignores events from an obsolete stream generation and aborts on unmount', async () => {
    const callbacks: Array<(event: RealtimeLogStreamEvent) => void> = []
    const signals: AbortSignal[] = []
    stream.mockImplementation(
      (_lastEventId, callback: (event: RealtimeLogStreamEvent) => void, signal: AbortSignal) => {
        callbacks.push(callback)
        signals.push(signal)
        return new Promise(() => undefined)
      },
    )
    const { controller, wrapper } = mountController()
    await nextTick()
    controller.reconnect()
    await nextTick()

    callbacks[0]?.(log('1'))
    callbacks[1]?.(log('2'))
    await new Promise((resolve) => setTimeout(resolve, 60))
    expect(controller.logs.value.map((item) => item.id)).toEqual([2])
    expect(signals[0]?.aborted).toBe(true)

    wrapper.unmount()
    expect(signals[1]?.aborted).toBe(true)
  })

  it('retries failed connections with 1 and 2 second delays', async () => {
    vi.useFakeTimers()
    stream.mockRejectedValue(new Error('offline'))
    const { wrapper } = mountController()
    await vi.waitFor(() => expect(stream).toHaveBeenCalledTimes(1))

    await vi.advanceTimersByTimeAsync(999)
    expect(stream).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(1)
    expect(stream).toHaveBeenCalledTimes(2)
    await vi.advanceTimersByTimeAsync(1999)
    expect(stream).toHaveBeenCalledTimes(2)
    await vi.advanceTimersByTimeAsync(1)
    expect(stream).toHaveBeenCalledTimes(3)
    wrapper.unmount()
  })
})

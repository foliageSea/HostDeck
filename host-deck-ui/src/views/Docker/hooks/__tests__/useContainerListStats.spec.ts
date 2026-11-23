import { effectScope, nextTick, ref } from 'vue'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { DockerContainerStats } from '@/api/docker'
import { useContainerListStats } from '../useContainerListStats'

const getContainerStats = vi.hoisted(() => vi.fn())
vi.mock('@/api/docker', () => ({ dockerApi: { getContainerStats } }))

const sample: DockerContainerStats = {
  id: '1',
  name: 'web',
  cpuPercent: '1.25%',
  memUsage: '24 MiB / 128 MiB',
  memPercent: '18.75%',
  netIO: '',
  timestamp: 1000,
  networkRxBytes: 1000,
  networkTxBytes: 2000,
  blockIO: '',
  pids: '1',
}

describe('useContainerListStats', () => {
  let scope: ReturnType<typeof effectScope>

  beforeEach(() => {
    scope = effectScope()
    vi.useFakeTimers()
    getContainerStats.mockReset()
  })

  afterEach(() => {
    scope.stop()
    vi.useRealTimers()
  })

  it('bounds concurrent requests and starts the next poll only after the current one finishes', async () => {
    const resolveRequests: (() => void)[] = []
    getContainerStats.mockImplementation(
      () => new Promise((resolve) => resolveRequests.push(() => resolve(sample))),
    )
    const stats = scope.run(() =>
      useContainerListStats(
        () => 'conn-1',
        () => ['1', '2', '3', '4', '5'],
      ),
    )!

    expect(getContainerStats).toHaveBeenCalledTimes(4)
    await vi.advanceTimersByTimeAsync(5000)
    expect(getContainerStats).toHaveBeenCalledTimes(4)

    resolveRequests.shift()?.()
    await vi.advanceTimersByTimeAsync(0)
    expect(stats.get('1')).toEqual(sample)
    expect(getContainerStats).toHaveBeenCalledTimes(5)

    resolveRequests.forEach((resolve) => resolve())
    await vi.advanceTimersByTimeAsync(5000)
    expect(getContainerStats).toHaveBeenCalledTimes(9)
  })

  it('aborts old page requests and ignores their results when the page changes or polling is disabled', async () => {
    let resolveOld!: (value: typeof sample) => void
    getContainerStats
      .mockImplementationOnce(() => new Promise((resolve) => (resolveOld = resolve)))
      .mockResolvedValue(sample)
    const connectionId = ref<string | undefined>('conn-1')
    const ids = ref(['old'])
    const stats = scope.run(() =>
      useContainerListStats(
        () => connectionId.value,
        () => ids.value,
      ),
    )!
    const oldSignal = getContainerStats.mock.calls[0]?.[2] as AbortSignal

    ids.value = ['new']
    await nextTick()
    resolveOld(sample)
    await vi.advanceTimersByTimeAsync(0)
    expect(oldSignal.aborted).toBe(true)
    expect(stats.has('old')).toBe(false)
    expect(stats.get('new')).toEqual(sample)

    connectionId.value = undefined
    await nextTick()
    expect(stats.size).toBe(0)
    await vi.advanceTimersByTimeAsync(5000)
    expect(getContainerStats).toHaveBeenCalledTimes(2)
  })

  it('clears a failed sample without affecting other containers', async () => {
    getContainerStats.mockResolvedValue(sample)
    const stats = scope.run(() =>
      useContainerListStats(
        () => 'conn-1',
        () => ['1', '2'],
      ),
    )!
    await vi.advanceTimersByTimeAsync(0)
    expect(stats.size).toBe(2)

    getContainerStats.mockRejectedValueOnce(new Error('Container stopped'))
    await vi.advanceTimersByTimeAsync(5000)
    expect(stats.has('1')).toBe(false)
    expect(stats.has('2')).toBe(true)
  })

  it('calculates network rates using sample timestamps and ignores reset counters', async () => {
    getContainerStats
      .mockResolvedValueOnce(sample)
      .mockResolvedValueOnce({
        ...sample,
        timestamp: 7000,
        networkRxBytes: 7000,
        networkTxBytes: 5000,
      })
      .mockResolvedValueOnce({
        ...sample,
        timestamp: 13000,
        networkRxBytes: 7000,
        networkTxBytes: 100,
      })
      .mockResolvedValue({ ...sample, timestamp: 13000, networkRxBytes: 8000 })
    const stats = scope.run(() =>
      useContainerListStats(
        () => 'conn-1',
        () => ['1'],
      ),
    )!

    await vi.advanceTimersByTimeAsync(0)
    expect(stats.get('1')?.networkRxBytesPerSecond).toBeUndefined()
    expect(stats.get('1')?.networkTxBytesPerSecond).toBeUndefined()

    await vi.advanceTimersByTimeAsync(5000)
    expect(stats.get('1')?.networkRxBytesPerSecond).toBe(1000)
    expect(stats.get('1')?.networkTxBytesPerSecond).toBe(500)

    await vi.advanceTimersByTimeAsync(5000)
    expect(stats.get('1')?.networkRxBytesPerSecond).toBe(0)
    expect(stats.get('1')?.networkTxBytesPerSecond).toBeUndefined()

    await vi.advanceTimersByTimeAsync(5000)
    expect(stats.get('1')?.networkRxBytesPerSecond).toBeUndefined()
    expect(stats.get('1')?.networkTxBytesPerSecond).toBeUndefined()
  })
})

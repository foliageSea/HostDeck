import { effectScope, nextTick, ref } from 'vue'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type {
  DockerContainerStats,
  DockerContainerStatsSample,
  DockerContainerStatsStreamEvent,
} from '@/api/docker'
import { getLiveContainerStats, subscribeContainerStats } from '../dockerContainerStatsStream'
import { useContainerListStats } from '../useContainerListStats'

const { getContainerStats, streamContainerStats } = vi.hoisted(() => ({
  getContainerStats: vi.fn(),
  streamContainerStats: vi.fn<typeof import('@/api/docker').dockerApi.streamContainerStats>(),
}))
vi.mock('@/api/docker', () => ({ dockerApi: { getContainerStats, streamContainerStats } }))

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

const streamSample: DockerContainerStatsSample = {
  id: '1',
  name: 'web',
  timestamp: 2000,
  cpuPercent: 3.5,
  memoryPercent: 25,
  memoryUsage: 32 * 1024 ** 2,
  memoryLimit: 128 * 1024 ** 2,
  networkRxBytes: 4000,
  networkTxBytes: 5000,
  networkRxBytesPerSecond: 3000,
  networkTxBytesPerSecond: 3000,
  blockReadBytes: 0,
  blockWriteBytes: 0,
  pids: 2,
}

interface StatsStream {
  signal: AbortSignal | undefined
  emit: (event: DockerContainerStatsStreamEvent) => void
  disconnect: (error: Error) => void
}

function mockStatsStreams() {
  const streams: StatsStream[] = []
  streamContainerStats.mockImplementation((_connectionId, _containerId, emit, signal) =>
    new Promise<void>((_resolve, reject) => {
      streams.push({ signal, emit, disconnect: reject })
      signal?.addEventListener('abort', () => reject(signal.reason), { once: true })
    }),
  )
  return streams
}

describe('useContainerListStats', () => {
  let scope: ReturnType<typeof effectScope>
  const releases = new Set<() => void>()

  function subscribe(...args: Parameters<typeof subscribeContainerStats>) {
    const unsubscribe = subscribeContainerStats(...args)
    const release = () => {
      releases.delete(release)
      unsubscribe()
    }
    releases.add(release)
    return release
  }

  beforeEach(() => {
    scope = effectScope()
    vi.useFakeTimers()
    getContainerStats.mockReset()
    streamContainerStats.mockReset()
  })

  afterEach(() => {
    scope.stop()
    releases.forEach((release) => release())
    vi.useRealTimers()
  })

  it('uses the latest shared SSE sample only on a poll and falls back to HTTP when unavailable', async () => {
    const streams = mockStatsStreams()
    const fallback = { ...sample, timestamp: 11_000 }
    getContainerStats.mockResolvedValueOnce(sample).mockResolvedValue(fallback)

    // A real subscription models the stats window opening before the list starts polling.
    const listener = vi.fn()
    const closeWindow = subscribe('conn-1', '1', listener)
    expect(streamContainerStats).toHaveBeenCalledTimes(1)
    const stream = streams[0]!
    stream.emit({ event: 'connected', data: {} })
    expect(getLiveContainerStats('conn-1', '1')).toBeUndefined()

    const stats = scope.run(() => useContainerListStats(() => 'conn-1', () => ['1']))!
    await vi.advanceTimersByTimeAsync(0)
    expect(getContainerStats).toHaveBeenNthCalledWith(1, 'conn-1', '1', expect.any(AbortSignal))
    expect(stats.get('1')).toEqual(sample)

    const latest = { ...streamSample, timestamp: 3000, cpuPercent: 6 }
    stream.emit({ event: 'stats', data: streamSample })
    stream.emit({ event: 'stats', data: latest })
    await vi.advanceTimersByTimeAsync(4999)
    expect(listener).toHaveBeenLastCalledWith(
      expect.objectContaining({ status: 'live', sample: latest }),
    )
    expect(stats.get('1')).toEqual(sample)
    expect(getContainerStats).toHaveBeenCalledTimes(1)

    await vi.advanceTimersByTimeAsync(1)
    expect(stats.get('1')).toMatchObject({
      timestamp: latest.timestamp,
      cpuPercent: '6.0%',
      memPercent: '25.0%',
      networkRxBytesPerSecond: latest.networkRxBytesPerSecond,
      networkTxBytesPerSecond: latest.networkTxBytesPerSecond,
    })
    expect(getContainerStats).toHaveBeenCalledTimes(1)

    stream.disconnect(new Error('Connection lost'))
    await vi.advanceTimersByTimeAsync(0)
    expect(listener).toHaveBeenLastCalledWith(expect.objectContaining({ status: 'reconnecting' }))
    expect(getLiveContainerStats('conn-1', '1')).toBeUndefined()
    expect(stats.get('1')?.timestamp).toBe(latest.timestamp)
    expect(getContainerStats).toHaveBeenCalledTimes(1)

    await vi.advanceTimersByTimeAsync(5000)
    expect(getContainerStats).toHaveBeenNthCalledWith(2, 'conn-1', '1', expect.any(AbortSignal))
    expect(stats.get('1')?.timestamp).toBe(fallback.timestamp)
    expect(streamContainerStats).toHaveBeenCalledTimes(2)
    const reconnected = streams[1]!
    reconnected.emit({ event: 'connected', data: {} })
    expect(getLiveContainerStats('conn-1', '1')).toBeUndefined()

    const fresh = { ...streamSample, timestamp: 13_000 }
    reconnected.emit({ event: 'stats', data: fresh })
    await vi.advanceTimersByTimeAsync(5000)
    expect(getContainerStats).toHaveBeenCalledTimes(2)
    expect(stats.get('1')?.timestamp).toBe(fresh.timestamp)

    closeWindow()
    expect(reconnected.signal?.aborted).toBe(true)
    expect(getLiveContainerStats('conn-1', '1')).toBeUndefined()
    await vi.advanceTimersByTimeAsync(5000)
    expect(getContainerStats).toHaveBeenNthCalledWith(3, 'conn-1', '1', expect.any(AbortSignal))
    expect(stats.get('1')?.timestamp).toBe(fallback.timestamp)
  })

  it('shares one stream per connection and container and immediately replays the current state', () => {
    const streams = mockStatsStreams()
    const first = vi.fn()
    const second = vi.fn()
    const releaseFirst = subscribe('conn-1', '1', first)
    expect(first).toHaveBeenLastCalledWith(
      expect.objectContaining({ status: 'connecting', error: '' }),
    )
    expect(streamContainerStats).toHaveBeenNthCalledWith(
      1,
      'conn-1',
      '1',
      expect.any(Function),
      expect.any(AbortSignal),
    )
    const stream = streams[0]!
    stream.emit({ event: 'connected', data: {} })
    stream.emit({ event: 'stats', data: streamSample })
    const releaseSecond = subscribe('conn-1', '1', second)
    expect(second).toHaveBeenLastCalledWith(
      expect.objectContaining({ status: 'live', error: '', sample: streamSample }),
    )
    expect(streamContainerStats).toHaveBeenCalledTimes(1)

    subscribe('conn-2', '1', vi.fn())
    subscribe('conn-1', '2', vi.fn())
    const keys = streamContainerStats.mock.calls.map(([connectionId, containerId]) => [
      connectionId,
      containerId,
    ])
    expect(keys).toEqual([
      ['conn-1', '1'],
      ['conn-2', '1'],
      ['conn-1', '2'],
    ])
    expect(getLiveContainerStats('conn-2', '1')).toBeUndefined()
    expect(getLiveContainerStats('conn-1', '2')).toBeUndefined()

    releaseFirst()
    expect(stream.signal?.aborted).toBe(false)
    first.mockClear()
    const latest = { ...streamSample, timestamp: 3000 }
    stream.emit({ event: 'stats', data: latest })
    expect(first).not.toHaveBeenCalled()
    expect(second).toHaveBeenLastCalledWith(expect.objectContaining({ sample: latest }))
    expect(getLiveContainerStats('conn-1', '1')).toEqual(latest)

    releaseSecond()
    expect(stream.signal?.aborted).toBe(true)
    expect(getLiveContainerStats('conn-1', '1')).toBeUndefined()
    expect(streams[1]?.signal?.aborted).toBe(false)
    expect(streams[2]?.signal?.aborted).toBe(false)
  })

  it('expires stalled samples even with connected events and cancels retry on final release', async () => {
    const streams = mockStatsStreams()
    const listener = vi.fn()
    const release = subscribe('conn-1', '1', listener)
    const stream = streams[0]!
    stream.emit({ event: 'connected', data: {} })
    stream.emit({ event: 'stats', data: streamSample })

    await vi.advanceTimersByTimeAsync(10_000)
    const latest = { ...streamSample, timestamp: 12_000 }
    stream.emit({ event: 'stats', data: latest })
    await vi.advanceTimersByTimeAsync(14_999)
    stream.emit({ event: 'connected', data: {} })
    expect(stream.signal?.aborted).toBe(false)
    expect(getLiveContainerStats('conn-1', '1')).toEqual(latest)

    await vi.advanceTimersByTimeAsync(1)
    expect(stream.signal?.aborted).toBe(true)
    expect(listener).toHaveBeenLastCalledWith(expect.objectContaining({ status: 'reconnecting' }))
    expect(getLiveContainerStats('conn-1', '1')).toBeUndefined()

    release()
    await vi.advanceTimersByTimeAsync(20_000)
    expect(streamContainerStats).toHaveBeenCalledTimes(1)
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

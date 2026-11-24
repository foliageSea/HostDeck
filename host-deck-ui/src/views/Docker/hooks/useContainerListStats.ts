import { shallowReactive, watch } from 'vue'
import { dockerApi, type DockerContainerStats, type DockerContainerStatsSample } from '@/api/docker'
import { getLiveContainerStats } from './dockerContainerStatsStream'

const POLL_DELAY_MS = 5000
const MAX_CONCURRENT_REQUESTS = 4

interface ContainerListStats extends Pick<
  DockerContainerStats,
  'cpuPercent' | 'memPercent' | 'memUsage' | 'timestamp' | 'networkRxBytes' | 'networkTxBytes'
> {
  networkRxBytesPerSecond?: number
  networkTxBytesPerSecond?: number
}

function formatMemoryBytes(bytes: number) {
  if (bytes <= 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
  let unit = 0
  while (bytes >= 1024 && unit < units.length - 1) {
    bytes /= 1024
    unit += 1
  }
  return bytes.toFixed(unit === 0 || bytes >= 10 ? 0 : 1) + ' ' + units[unit]
}

function toListStats(sample: DockerContainerStatsSample): ContainerListStats {
  return {
    cpuPercent: sample.cpuPercent.toFixed(1) + '%',
    memPercent: sample.memoryPercent.toFixed(1) + '%',
    memUsage: formatMemoryBytes(sample.memoryUsage) + ' / ' + formatMemoryBytes(sample.memoryLimit),
    timestamp: sample.timestamp,
    networkRxBytes: sample.networkRxBytes,
    networkTxBytes: sample.networkTxBytes,
    networkRxBytesPerSecond: sample.networkRxBytesPerSecond,
    networkTxBytesPerSecond: sample.networkTxBytesPerSecond,
  }
}

function getNetworkRate(current: number, previous: number, elapsedSeconds: number) {
  const delta = current - previous
  if (
    Number.isFinite(delta) &&
    delta >= 0 &&
    Number.isFinite(elapsedSeconds) &&
    elapsedSeconds > 0
  ) {
    return delta / elapsedSeconds
  }
}

export function useContainerListStats(
  getConnectionId: () => string | null | undefined,
  getContainerIds: () => string[],
) {
  const stats = shallowReactive(new Map<string, ContainerListStats>())

  watch(
    [getConnectionId, getContainerIds],
    ([connectionId, ids], _previous, onCleanup) => {
      stats.clear()
      if (!connectionId || ids.length === 0) return

      const controller = new AbortController()
      const { signal } = controller
      let timer: ReturnType<typeof setTimeout> | undefined
      onCleanup(() => {
        controller.abort()
        clearTimeout(timer)
      })

      async function poll(connectionId: string) {
        let next = 0
        const worker = async () => {
          while (!signal.aborted && next < ids.length) {
            const id = ids[next++]
            if (id === undefined) return
            const applyLiveSample = () => {
              const live = getLiveContainerStats(connectionId, id)
              if (!live) return false
              stats.set(id, toListStats(live))
              return true
            }
            if (applyLiveSample()) continue
            try {
              const sample = await dockerApi.getContainerStats(connectionId, id, signal)
              if (signal.aborted) return
              // The window may have received its first sample while the request was in flight.
              if (applyLiveSample()) continue
              const previous = stats.get(id)
              if (!previous) {
                stats.set(id, sample)
                continue
              }
              const elapsed = (sample.timestamp - previous.timestamp) / 1000
              stats.set(id, {
                ...sample,
                networkRxBytesPerSecond: getNetworkRate(
                  sample.networkRxBytes,
                  previous.networkRxBytes,
                  elapsed,
                ),
                networkTxBytesPerSecond: getNetworkRate(
                  sample.networkTxBytes,
                  previous.networkTxBytes,
                  elapsed,
                ),
              })
            } catch {
              if (!signal.aborted && !applyLiveSample()) stats.delete(id)
            }
          }
        }

        await Promise.all(
          Array.from({ length: Math.min(ids.length, MAX_CONCURRENT_REQUESTS) }, worker),
        )
        if (!signal.aborted) timer = setTimeout(() => void poll(connectionId), POLL_DELAY_MS)
      }

      void poll(connectionId)
    },
    { immediate: true },
  )

  return stats
}

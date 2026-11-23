import { shallowReactive, watch } from 'vue'
import { dockerApi, type DockerContainerStats } from '@/api/docker'

const POLL_DELAY_MS = 5000
const MAX_CONCURRENT_REQUESTS = 4

interface ContainerListStats extends DockerContainerStats {
  networkRxBytesPerSecond?: number
  networkTxBytesPerSecond?: number
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
            try {
              const sample = await dockerApi.getContainerStats(connectionId, id, signal)
              if (signal.aborted) return
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
              if (!signal.aborted) stats.delete(id)
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

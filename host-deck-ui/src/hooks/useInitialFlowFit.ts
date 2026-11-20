import { computed, ref, watch } from 'vue'
import { useNodesInitialized, useVueFlow } from '@vue-flow/core'

/** Fit the first measured graph before revealing it, without disturbing later viewport changes.
 * Keep the canvas mounted and hide it with opacity: Vue Flow sets visibility on each node.
 */
export function useInitialFlowFit(id: string, padding: number, isActive = () => true) {
  const { fitView, viewportHelper } = useVueFlow(id)
  const nodesInitialized = useNodesInitialized()
  const viewportInitialized = computed(() => viewportHelper.value.viewportInitialized)
  const flowReady = ref(false)

  watch(
    [isActive, nodesInitialized, viewportInitialized],
    async ([active, nodesReady, viewportReady], _, onCleanup) => {
      if (!active) {
        flowReady.value = false
        return
      }
      if (flowReady.value || !nodesReady || !viewportReady) return

      let stale = false
      onCleanup(() => { stale = true })
      const fitted = await fitView({ padding, maxZoom: 1, duration: 0 })
      if (fitted && !stale) flowReady.value = true
    },
    { flush: 'post', immediate: true },
  )

  return { flowReady }
}

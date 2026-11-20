import { flushPromises } from '@vue/test-utils'
import { effectScope, nextTick, ref } from 'vue'
import { describe, expect, it, vi } from 'vitest'
import { useInitialFlowFit } from '../useInitialFlowFit'

const { fitView } = vi.hoisted(() => ({ fitView: vi.fn() }))
const nodesInitialized = ref(false)
const viewportHelper = ref({ viewportInitialized: false })

vi.mock('@vue-flow/core', () => ({
  useVueFlow: () => ({ fitView, viewportHelper }),
  useNodesInitialized: () => nodesInitialized,
}))

function setup(active = ref(true)) {
  fitView.mockReset().mockResolvedValue(true)
  nodesInitialized.value = false
  viewportHelper.value.viewportInitialized = false
  const scope = effectScope()
  const { flowReady } = scope.run(() => useInitialFlowFit('test-flow', 0.12, () => active.value))!
  return { flowReady, stop: () => scope.stop() }
}

describe('useInitialFlowFit', () => {
  it.each([true, false])('waits for both nodes and viewport (nodes first: %s)', async (nodesFirst) => {
    const { flowReady, stop } = setup()
    try {
      let resolveFit!: (fitted: boolean) => void
      fitView.mockReturnValueOnce(new Promise<boolean>((resolve) => { resolveFit = resolve }))

      nodesInitialized.value = nodesFirst
      viewportHelper.value.viewportInitialized = !nodesFirst
      await nextTick()
      expect(flowReady.value).toBe(false)
      expect(fitView).not.toHaveBeenCalled()

      nodesInitialized.value = true
      viewportHelper.value.viewportInitialized = true
      await nextTick()
      expect(fitView).toHaveBeenCalledExactlyOnceWith({ padding: 0.12, maxZoom: 1, duration: 0 })
      expect(flowReady.value).toBe(false)

      resolveFit(true)
      await flushPromises()
      expect(flowReady.value).toBe(true)

      nodesInitialized.value = false
      await nextTick()
      nodesInitialized.value = true
      await nextTick()
      expect(flowReady.value).toBe(true)
      expect(fitView).toHaveBeenCalledTimes(1)
    } finally {
      stop()
    }
  })

  it('fits again when the diagram tab is reopened, ignoring a stale fit', async () => {
    const active = ref(false)
    const { flowReady, stop } = setup(active)
    try {
      let resolveFit!: (fitted: boolean) => void
      fitView.mockReturnValueOnce(new Promise<boolean>((resolve) => { resolveFit = resolve }))
      nodesInitialized.value = true
      viewportHelper.value.viewportInitialized = true
      await nextTick()
      expect(fitView).not.toHaveBeenCalled()

      active.value = true
      await nextTick()
      expect(fitView).toHaveBeenCalledTimes(1)

      active.value = false
      await nextTick()
      resolveFit(true)
      await flushPromises()
      expect(flowReady.value).toBe(false)

      active.value = true
      await flushPromises()
      expect(fitView).toHaveBeenCalledTimes(2)
      expect(flowReady.value).toBe(true)
    } finally {
      stop()
    }
  })
})

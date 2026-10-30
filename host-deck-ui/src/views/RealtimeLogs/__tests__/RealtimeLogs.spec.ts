import { flushPromises, mount } from '@vue/test-utils'
import { nextTick } from 'vue'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { RealtimeLogStreamEvent } from '@/api/logs'
import RealtimeLogs from '../index.vue'

const { stream } = vi.hoisted(() => ({ stream: vi.fn() }))

vi.mock('@/api/logs', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/api/logs')>()),
  logsApi: { stream },
}))

vi.mock('@/stores/settings', () => ({ useSettingsStore: () => ({ isDark: true }) }))
vi.mock('../useServerMetrics', async () => {
  const { ref } = await import('vue')
  return {
    useServerMetrics: () => ({
      snapshot: ref(null),
      connectionStatus: ref('connected'),
      reconnect: vi.fn(),
    }),
  }
})

function mountLogs() {
  let onEvent: (event: RealtimeLogStreamEvent) => void
  stream.mockImplementation((_lastEventId, callback) => {
    onEvent = callback
    return new Promise(() => undefined)
  })
  const wrapper = mount(RealtimeLogs, {
    global: {
      stubs: {
        NSelect: true,
        NInput: true,
        NSwitch: true,
        NButton: true,
        NTooltip: true,
      },
    },
  })
  const output = wrapper.get<HTMLElement>('.log-output')
  Object.defineProperties(output.element, {
    clientHeight: { value: 100 },
    scrollHeight: {
      get: () =>
        Array.from(output.element.querySelectorAll('.log-entry')).reduce(
          (height, entry) => height + Number(entry.textContent?.match(/message-(\d+)/)?.[1] ?? 0),
          0,
        ),
    },
  })

  async function append(firstId: number, count = 1) {
    for (let id = firstId; id < firstId + count; id += 1) {
      onEvent({
        event: 'log',
        id: String(id),
        data: {
          id,
          timestamp: '2026-08-13T00:00:00.000Z',
          level: 'INFO',
          levelValue: 800,
          logger: 'test',
          message: `message-${id}`,
        },
      })
    }
    await vi.advanceTimersByTimeAsync(50)
    await flushPromises()
  }

  return { wrapper, output, append }
}

describe('RealtimeLogs auto scroll', () => {
  afterEach(() => {
    vi.useRealTimers()
    stream.mockReset()
  })

  it('keeps following new logs after the 500-entry buffer is full', async () => {
    vi.useFakeTimers()
    const { wrapper, output, append } = mountLogs()
    try {
      await append(1, 500)
      expect(output.element.scrollTop).toBe(output.element.scrollHeight)
      const previousHeight = output.element.scrollHeight

      await append(501)
      expect(wrapper.findAll('.log-entry')).toHaveLength(500)
      expect(output.element.scrollHeight).toBeGreaterThan(previousHeight)
      expect(output.element.scrollTop).toBe(output.element.scrollHeight)
    } finally {
      wrapper.unmount()
    }
  })

  it('preserves reading position and resumes following when jumping to latest', async () => {
    vi.useFakeTimers()
    const { wrapper, output, append } = mountLogs()
    try {
      await append(1, 500)
      output.element.scrollTop = 100
      await output.trigger('scroll')

      await append(501)
      expect(output.element.scrollTop).toBe(100)

      await wrapper.get('.jump-latest').trigger('click')
      await nextTick()
      expect(output.element.scrollTop).toBe(output.element.scrollHeight)

      await append(502)
      expect(output.element.scrollTop).toBe(output.element.scrollHeight)
    } finally {
      wrapper.unmount()
    }
  })
})

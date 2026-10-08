import { createPinia, setActivePinia } from 'pinia'
import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { MonitorResponse } from '@/api/system'
import { systemApi } from '@/api/system'
import { useSshStore } from '@/stores/ssh'
import PerformanceMonitorWidget from '../PerformanceMonitorWidget.vue'

vi.mock('@/api/system', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/api/system')>()
  return {
    ...original,
    systemApi: {
      getMonitorHistory: vi.fn(),
    },
  }
})

function createSample(timestamp: number, cpuUsage: number): MonitorResponse {
  return {
    cpu: '0.40',
    cpuUsage,
    disk: '55%',
    network: {
      downloadSpeed: 4096,
      uploadSpeed: 2048,
    },
    ram: {
      free: 4096,
      total: 8192,
      used: 4096,
    },
    systemInfo: {
      architecture: 'x86_64',
      bootTime: 'today',
      distribution: 'Linux',
      hostAddress: '10.0.0.1',
      hostname: 'demo-host',
      kernel: '6.0',
      uptime: '1 hour',
    },
    timestamp,
  }
}

describe('PerformanceMonitorWidget', () => {
  beforeEach(() => {
    window.localStorage.clear()
    Object.defineProperty(window, 'matchMedia', {
      configurable: true,
      value: vi.fn().mockReturnValue({
        addEventListener: vi.fn(),
        matches: false,
        removeEventListener: vi.fn(),
      }),
    })
    vi.mocked(systemApi.getMonitorHistory).mockReset()
    setActivePinia(createPinia())
  })

  it('loads recent history and renders current performance values', async () => {
    vi.mocked(systemApi.getMonitorHistory).mockResolvedValue([createSample(1000, 25)])
    const sshStore = useSshStore()
    sshStore.connectionId = 'connection-1'
    sshStore.host = '10.0.0.1'

    const wrapper = mount(PerformanceMonitorWidget)
    await flushPromises()

    expect(systemApi.getMonitorHistory).toHaveBeenCalledWith('connection-1', 20)
    expect(wrapper.text()).toContain('demo-host')
    expect(wrapper.text()).toContain('25.0%')
    expect(wrapper.text()).toContain('50.0%')
    expect(wrapper.text()).toContain('55.0%')
    expect(wrapper.text()).toContain('2.0 KB/s')
    expect(wrapper.text()).toContain('4.0 KB/s')
  })

  it('merges live samples and limits each sparkline to twenty points', async () => {
    vi.mocked(systemApi.getMonitorHistory).mockResolvedValue(
      Array.from({ length: 25 }, (_, index) => createSample(index + 1, index)),
    )
    const sshStore = useSshStore()
    sshStore.connectionId = 'connection-1'
    const wrapper = mount(PerformanceMonitorWidget)
    await flushPromises()

    const firstPoints = (wrapper.get('polyline').attributes('points') ?? '').split(' ')
    expect(firstPoints).toHaveLength(20)

    sshStore.monitorData = createSample(30, 72.5)
    await wrapper.vm.$nextTick()
    expect(wrapper.text()).toContain('72.5%')
    expect((wrapper.get('polyline').attributes('points') ?? '').split(' ')).toHaveLength(20)
  })

  it('shows the monitor error while retaining the latest sample', async () => {
    vi.mocked(systemApi.getMonitorHistory).mockResolvedValue([createSample(1000, 25)])
    const sshStore = useSshStore()
    sshStore.connectionId = 'connection-1'
    const wrapper = mount(PerformanceMonitorWidget)
    await flushPromises()

    sshStore.monitorError = 'monitor failed'
    await wrapper.vm.$nextTick()

    expect(wrapper.text()).toContain('采样异常')
    expect(wrapper.text()).toContain('25.0%')
  })
})

import { enableAutoUnmount, flushPromises, shallowMount } from '@vue/test-utils'
import { afterEach, expect, it, vi } from 'vitest'
import BackendPortsSection from '../BackendPortsSection.vue'

const { getBackendPorts } = vi.hoisted(() => ({ getBackendPorts: vi.fn() }))

vi.mock('@/api/settings', () => ({ settingsApi: { getBackendPorts } }))

enableAutoUnmount(afterEach)

it('shows IDE listeners and public proxy paths and removes stopped listeners on refresh', async () => {
  getBackendPorts.mockResolvedValueOnce({
    items: [
      {
        id: 'ide-abcdef123456',
        type: 'ide',
        name: '远程 IDE',
        host: '127.0.0.1',
        port: 49153,
        purpose: 'IDE 内部隧道，访问 /ide/abcdef123456/',
        status: 'running',
        target: '127.0.0.1:18090',
        connectionId: 'connection-1',
      },
      {
        id: 'port-forward-8',
        type: 'port-forward',
        name: 'HTTP 应用',
        host: '127.0.0.1',
        port: 49154,
        purpose: 'HTTP 转发内部隧道，访问 /port-forward/8/',
        status: 'running',
      },
    ],
  })
  const wrapper = shallowMount(BackendPortsSection, {
    global: {
      stubs: {
        NTooltip: { template: '<div><slot name="trigger" /></div>' },
        NButton: { template: '<button><slot /></button>' },
        NIcon: true,
        NTag: { template: '<span><slot /></span>' },
        NSpin: true,
        NAlert: true,
        NEmpty: true,
      },
    },
  })
  await flushPromises()

  expect(wrapper.text()).toContain('远程 IDE')
  expect(wrapper.text()).toContain('127.0.0.1:49153')
  expect(wrapper.text()).toContain('目标：127.0.0.1:18090')
  expect(wrapper.text()).toContain('/ide/abcdef123456/')
  expect(wrapper.text()).toContain('/port-forward/8/')

  getBackendPorts.mockResolvedValueOnce({ items: [] })
  await wrapper.get('button').trigger('click')
  await flushPromises()
  expect(wrapper.findAll('.backend-port-row')).toHaveLength(0)
})

import { flushPromises, shallowMount } from '@vue/test-utils'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { defineComponent } from 'vue'
import type { DockerViewController } from '../useDockerView'
import DockerContainersTab from '../../components/DockerContainersTab.vue'

const { list } = vi.hoisted(() => ({ list: vi.fn() }))
vi.mock('@/api/port-forward', () => ({ portForwardApi: { list } }))
vi.mock('@/lib/ui', () => ({ getUiApi: () => ({ message: { error: vi.fn() } }) }))

const Dropdown = defineComponent({
  name: 'NDropdown', props: ['options'], emits: ['select'], template: '<div><slot /></div>',
})
const Slot = defineComponent({ template: '<div><slot /></div>' })
const wrappers: Array<{ unmount(): void }> = []
afterEach(() => { wrappers.splice(0).forEach((wrapper) => wrapper.unmount()); vi.resetAllMocks() })

function mountMenu() {
  const container = { id: 'web', name: 'web', state: 'running', status: 'Up', ports: ['0.0.0.0:5099->5099/tcp'], networks: [] }
  const controller = {
    containers: [container], containerTotal: 1, containerPagination: {},
    getContainerPortUrl: () => 'http://host:5099', isContainerPortPinned: () => false,
    formatTime: () => '',
  } as unknown as DockerViewController
  const view = shallowMount(DockerContainersTab, { props: { controller }, global: { stubs: {
    NDropdown: Dropdown, NTooltip: { template: '<div><slot name="trigger" /></div>' },
    NModal: { template: '<div><slot /><slot name="action" /></div>' },
    NSpace: Slot, NButton: Slot, NTag: Slot, NSwitch: true, NPagination: true,
    NEmpty: true, NInput: true, NSelect: true, NIcon: true,
  } } })
  wrappers.push(view)
  const portDropdown = view.findAllComponents(Dropdown).find((item) =>
    item.props('options')?.some((option: { key: string }) => option.key.startsWith('port:')),
  )!
  portDropdown.vm.$emit('select', 'port:0.0.0.0:5099->5099/tcp')
  const options = () => view.findAllComponents(Dropdown).flatMap((item) => item.props('options') ?? []) as Array<{ key: string; label: string; disabled?: boolean }>
  return { view, options }
}

describe('Docker port menu loads saved forwards when opened', () => {
  it('shows open forward immediately for a saved running rule', async () => {
    list.mockResolvedValue([{ protocol: 'http', remoteHost: '127.0.0.1', remotePort: 5099, status: 'running', accessPath: '/port-forward/12/' }])
    const { view, options } = mountMenu()
    await flushPromises()
    expect(list).toHaveBeenCalledOnce()
    expect(options().find((option) => option.key === 'open-forward')?.label).toBe('打开转发')
    expect(options().some((option) => option.key === 'create-forward')).toBe(false)
    expect(view.text()).toContain('/port-forward/12/')
  })

  it('offers starting an existing stopped rule', async () => {
    list.mockResolvedValue([{ protocol: 'http', remoteHost: '127.0.0.1', remotePort: 5099, status: 'stopped' }])
    const { options } = mountMenu()
    await flushPromises()
    expect(options().find((option) => option.key === 'create-forward')?.label).toBe('启动 HTTP 转发')
  })

  it('only offers creation after the list confirms there is no match', async () => {
    let resolve!: (rules: unknown[]) => void
    list.mockReturnValue(new Promise((done) => { resolve = done }))
    const { options } = mountMenu()
    await flushPromises()
    expect(options().find((option) => option.key === 'create-forward')).toMatchObject({ label: '正在检查转发', disabled: true })
    resolve([])
    await flushPromises()
    expect(options().find((option) => option.key === 'create-forward')).toMatchObject({ label: '创建 HTTP 转发', disabled: false })
  })
})

import { flushPromises, shallowMount } from '@vue/test-utils'
import { defineComponent } from 'vue'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import PortForwardView from '../index.vue'

const mocks = vi.hoisted(() => ({
  create: vi.fn(), list: vi.fn(), fitView: vi.fn(),
}))
vi.mock('@/api/port-forward', () => ({ portForwardApi: mocks }))
vi.mock('@/stores/settings', () => ({ useSettingsStore: () => ({ isDark: false }) }))
vi.mock('@/stores/ssh', () => ({ useSshStore: () => ({
  connectionId: 'conn-1', isConnected: true, username: 'user', host: 'host', port: 22,
}) }))
vi.mock('@/lib/ui', () => ({ getUiApi: () => ({
  message: { success: vi.fn(), error: vi.fn(), warning: vi.fn() },
}) }))
vi.mock('@vue-flow/core', () => ({
  useVueFlow: () => ({ fitView: mocks.fitView }),
  Position: { Left: 'left', Right: 'right' },
  VueFlow: { template: '<div />' },
  Handle: { template: '<div />' },
}))

const Slot = defineComponent({ template: '<div><slot /></div>' })
const Button = defineComponent({ emits: ['click'], template: '<button @click="$emit(\'click\')"><slot /></button>' })
const Form = defineComponent({
  setup(_, { expose }) {
    expose({ validate: vi.fn().mockResolvedValue(undefined), restoreValidation: vi.fn() })
  },
  template: '<form><slot /></form>',
})

beforeEach(() => {
  vi.resetAllMocks()
  mocks.list.mockResolvedValue([])
  mocks.create.mockResolvedValue({ id: 12, protocol: 'http', status: 'running' })
})

describe('PortForward protocol form', () => {
  it('hides TCP fields and saves HTTP without a local listener configuration', async () => {
    const view = shallowMount(PortForwardView, {
      global: { stubs: {
        NModal: defineComponent({ template: '<div><slot /><slot name="footer" /></div>' }),
        NForm: Form,
        NFormItem: Slot,
        NButton: Button,
        NTooltip: defineComponent({ template: '<div><slot name="trigger" /></div>' }),
        NTag: true,
        NSwitch: true,
        NSpin: true,
        NEmpty: true,
        NInput: defineComponent({ name: 'NInput', emits: ['update:value'], template: '<input />' }),
        NInputNumber: defineComponent({ name: 'NInputNumber', emits: ['update:value'], template: '<input />' }),
        NRadioGroup: defineComponent({ name: 'NRadioGroup', emits: ['update:value'], template: '<div><slot /></div>' }),
        NRadioButton: true,
      } },
    })
    await flushPromises()
    view.findAll('button').find((button) => button.text() === '新增转发')!.trigger('click')
    await flushPromises()
    expect(view.findAllComponents({ name: 'NInputNumber' })).toHaveLength(2)
    view.findComponent({ name: 'NRadioGroup' }).vm.$emit('update:value', 'http')
    await flushPromises()
    expect(view.findAllComponents({ name: 'NInputNumber' })).toHaveLength(1)
    view.findAllComponents({ name: 'NInput' })[0]!.vm.$emit('update:value', 'Web')
    view.findComponent({ name: 'NInputNumber' }).vm.$emit('update:value', 3000)
    await flushPromises()
    await view.findAll('button').find((button) => button.text() === '保存')!.trigger('click')
    await flushPromises()
    expect(mocks.create).toHaveBeenCalledWith({
      protocol: 'http', name: 'Web', enabled: true, connectionId: 'conn-1',
      remoteHost: '127.0.0.1', remotePort: 3000, bindHost: undefined, localPort: undefined,
    })
    view.unmount()
  })
})

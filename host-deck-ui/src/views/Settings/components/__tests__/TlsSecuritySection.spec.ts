import { enableAutoUnmount, flushPromises, shallowMount } from '@vue/test-utils'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import TlsSecuritySection from '../TlsSecuritySection.vue'

const { getTlsSettings, saveTlsSettings, success, error } = vi.hoisted(() => ({
  getTlsSettings: vi.fn(),
  saveTlsSettings: vi.fn(),
  success: vi.fn(),
  error: vi.fn(),
}))
vi.mock('@/api/settings', () => ({ settingsApi: { getTlsSettings, saveTlsSettings } }))
vi.mock('@/lib/ui', () => ({ getUiApi: () => ({ message: { success, error } }) }))

enableAutoUnmount(afterEach)
beforeEach(() => vi.clearAllMocks())

const config = {
  enabled: false,
  source: 'selfSigned',
  hosts: ['localhost', '127.0.0.1', '::1'],
  certificate: null,
}
function mount() {
  return shallowMount(TlsSecuritySection, {
    global: {
      stubs: {
        NSpin: { template: '<div><slot /></div>' },
        NForm: { template: '<form><slot /></form>' },
        NFormItem: { template: '<div><slot /></div>' },
        NSpace: { template: '<div><slot /></div>' },
        NRadioGroup: { template: '<div><slot /></div>' },
        NRadio: true,
        NSwitch: {
          props: ['value'],
          emits: ['update:value'],
          template:
            '<button type="button" data-switch @click="$emit(\'update:value\', !value)">toggle</button>',
        },
        NButton: { template: '<button type="button"><slot /></button>' },
        NTag: { template: '<span><slot /></span>' },
        NInput: true,
      },
    },
  })
}

it('saves enabled state while retaining the active HTTP status until restart', async () => {
  getTlsSettings.mockResolvedValue({
    saved: config,
    active: config,
    restartRequired: false,
    managedExternally: false,
  })
  saveTlsSettings.mockResolvedValue({
    saved: { ...config, enabled: true },
    active: config,
    restartRequired: true,
    managedExternally: false,
  })
  const wrapper = mount()
  await flushPromises()
  await wrapper.get('[data-switch]').trigger('click')
  await wrapper
    .findAll('button')
    .find((button) => button.text() === '保存')!
    .trigger('click')
  await flushPromises()
  expect(saveTlsSettings).toHaveBeenCalledWith(
    expect.objectContaining({ enabled: true, source: 'selfSigned' }),
  )
  expect(wrapper.text()).toContain('当前 HTTP')
  expect(wrapper.text()).toContain('待重启生效')
})

it('shows a save failure without displaying a pending restart', async () => {
  getTlsSettings.mockResolvedValue({
    saved: config,
    active: config,
    restartRequired: false,
    managedExternally: false,
  })
  saveTlsSettings.mockRejectedValue(new Error('证书无效'))
  const wrapper = mount()
  await flushPromises()
  await wrapper
    .findAll('button')
    .find((button) => button.text() === '保存')!
    .trigger('click')
  await flushPromises()
  expect(error).toHaveBeenCalledWith('证书无效')
  expect(wrapper.text()).not.toContain('待重启生效')
})

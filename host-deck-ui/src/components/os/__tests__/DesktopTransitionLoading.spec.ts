import { mount } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import DesktopTransitionLoading from '../DesktopTransitionLoading.vue'

vi.mock('@/stores/settings', () => ({ useSettingsStore: () => ({ isDark: false }) }))

describe('desktop connection overlay', () => {
  it('offers a reachable cancellation action only while connecting', async () => {
    const wrapper = mount(DesktopTransitionLoading, {
      props: {
        show: true,
        cancellable: true,
        endpoint: 'user@example.com:22',
        serverName: 'Server',
      },
      global: {
        stubs: {
          BrandLogo: true,
          NButton: {
            emits: ['click'],
            template: '<button @click="$emit(\'click\')"><slot /></button>',
          },
        },
      },
    })
    expect(wrapper.get('button').text()).toBe('取消连接')
    await wrapper.get('button').trigger('click')
    expect(wrapper.emitted('cancel')).toHaveLength(1)
    await wrapper.setProps({ cancellable: false })
    expect(wrapper.find('button').exists()).toBe(false)
    wrapper.unmount()
  })
})

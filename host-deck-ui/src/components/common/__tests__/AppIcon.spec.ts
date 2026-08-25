import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import terminalIconUrl from '@/assets/app-icons/mac-tahoe/terminal.svg'
import AppIcon from '../AppIcon.vue'

describe('AppIcon', () => {
  it('renders the MacTahoe asset in themed mode', () => {
    const wrapper = mount(AppIcon, {
      props: { name: 'terminal', size: 42, themed: true },
    })
    const image = wrapper.get('img')

    expect(image.attributes('src')).toBe(terminalIconUrl)
    expect(image.attributes('width')).toBe('42')
    expect(image.attributes('height')).toBe('42')
  })

  it('keeps the compact component icon outside themed surfaces', () => {
    const wrapper = mount(AppIcon, {
      props: { name: 'terminal', size: 16 },
      global: {
        stubs: {
          NIcon: { template: '<span data-testid="component-icon"><slot /></span>' },
        },
      },
    })

    expect(wrapper.find('img').exists()).toBe(false)
    expect(wrapper.get('[data-testid="component-icon"]')).toBeTruthy()
  })
})

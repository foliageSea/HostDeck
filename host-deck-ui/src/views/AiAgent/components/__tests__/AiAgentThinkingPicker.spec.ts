import { defineComponent } from 'vue'
import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import AiAgentThinkingPicker from '../AiAgentThinkingPicker.vue'

function mountPicker(disabled = false) {
  return mount(AiAgentThinkingPicker, {
    props: {
      modelName: 'Thinking Model',
      provider: 'openai',
      levels: ['low', 'high', 'xhigh'],
      value: 'high',
      disabled,
    },
    global: {
      stubs: {
        NPopover: defineComponent({ template: '<div><slot name="trigger" /><slot /></div>' }),
      },
    },
  })
}

describe('AiAgentThinkingPicker', () => {
  it('uses model-specific stops and updates the label, range value and selection', async () => {
    const wrapper = mountPicker()
    const slider = wrapper.get('input[type="range"]')
    expect(slider.attributes('max')).toBe('3')
    expect(slider.attributes('aria-valuetext')).toBe('高')
    expect((slider.element as HTMLInputElement).value).toBe('2')
    expect(wrapper.text()).toContain('Thinking Model · openai')

    await slider.setValue('3')
    expect(wrapper.emitted('update:value')?.at(-1)).toEqual(['xhigh'])
    await wrapper.setProps({ value: 'xhigh' })
    expect(slider.attributes('aria-valuetext')).toBe('超高')
    expect(wrapper.get('.agent-thinking-trigger').text()).toContain('超高')

    await wrapper.get('[aria-label="恢复默认思考强度"]').trigger('click')
    expect(wrapper.emitted('update:value')?.at(-1)).toEqual(['default'])
  })

  it('prevents changes while a run or model switch is in progress', async () => {
    const wrapper = mountPicker(true)
    expect(wrapper.get('.agent-thinking-trigger').attributes('disabled')).toBeDefined()
    expect(wrapper.get('input').attributes('disabled')).toBeDefined()
    await wrapper.get('input').setValue('1')
    await wrapper.get('[aria-label="恢复默认思考强度"]').trigger('click')
    expect(wrapper.emitted('update:value')).toBeUndefined()
  })
})

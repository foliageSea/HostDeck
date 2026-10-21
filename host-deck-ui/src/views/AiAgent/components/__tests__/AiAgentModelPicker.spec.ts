import { defineComponent } from 'vue'
import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import AiAgentModelPicker from '../AiAgentModelPicker.vue'

const groups = [
  {
    provider: 'deepseek',
    models: [
      {
        id: 'deepseek-chat',
        key: 'deepseek:deepseek-chat',
        label: 'DeepSeek Chat',
        provider: 'deepseek',
        hasCredentials: true,
      },
      {
        id: 'deepseek-reasoner',
        key: 'deepseek:deepseek-reasoner',
        label: 'DeepSeek Reasoner',
        provider: 'deepseek',
        hasCredentials: false,
      },
    ],
  },
]

function mountPicker(overrides: Record<string, unknown> = {}) {
  return mount(AiAgentModelPicker, {
    props: {
      modelName: 'DeepSeek Chat',
      provider: 'deepseek',
      groups,
      activeProvider: 'deepseek',
      activeModel: 'deepseek-chat',
      levels: ['low', 'high', 'xhigh'],
      thinking: 'high',
      ...overrides,
    },
    global: {
      stubs: {
        NPopover: defineComponent({ template: '<div><slot name="trigger" /><slot /></div>' }),
      },
    },
  })
}

describe('AiAgentModelPicker', () => {
  it('shows the active model and reasoning level on the trigger', () => {
    const wrapper = mountPicker()
    expect(wrapper.get('.agent-model-trigger').text()).toContain('DeepSeek Chat')
    expect(wrapper.get('.agent-model-trigger').text()).toContain('高')
    expect(wrapper.findAll('.agent-model-row')).toHaveLength(2)
  })

  it('selects a model from the model view', async () => {
    const wrapper = mountPicker()
    await wrapper.findAll('.agent-model-row')[0]!.trigger('click')

    const options = wrapper.findAll('.agent-model-option')
    expect(options).toHaveLength(2)
    expect(options[0]!.attributes('aria-pressed')).toBe('true')
    expect(options[1]!.attributes('disabled')).toBeDefined()

    await options[0]!.trigger('click')
    expect(wrapper.emitted('select')?.at(-1)).toEqual(['deepseek', 'deepseek-chat'])

    await wrapper.get('.agent-model-back').trigger('click')
    expect(wrapper.findAll('.agent-model-row')).toHaveLength(2)
  })

  it('adjusts the reasoning level with model-specific stops', async () => {
    const wrapper = mountPicker()
    await wrapper.findAll('.agent-model-row')[1]!.trigger('click')

    const slider = wrapper.get('input[type="range"]')
    expect(slider.attributes('max')).toBe('3')
    expect(slider.attributes('aria-valuetext')).toBe('高')
    expect((slider.element as HTMLInputElement).value).toBe('2')
    expect(wrapper.text()).toContain('DeepSeek Chat · deepseek')

    await slider.setValue('3')
    expect(wrapper.emitted('update:thinking')?.at(-1)).toEqual(['xhigh'])

    await wrapper.get('[aria-label="恢复默认推理等级"]').trigger('click')
    expect(wrapper.emitted('update:thinking')?.at(-1)).toEqual(['default'])
  })

  it('prevents changes while a run or model switch is in progress', async () => {
    const wrapper = mountPicker({ disabled: true })
    expect(wrapper.get('.agent-model-trigger').attributes('disabled')).toBeDefined()

    await wrapper.findAll('.agent-model-row')[1]!.trigger('click')
    expect(wrapper.get('input').attributes('disabled')).toBeDefined()
    await wrapper.get('input').setValue('1')
    await wrapper.get('[aria-label="恢复默认推理等级"]').trigger('click')
    expect(wrapper.emitted('update:thinking')).toBeUndefined()
  })
})

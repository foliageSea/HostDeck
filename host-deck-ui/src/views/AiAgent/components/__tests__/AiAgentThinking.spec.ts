import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import AiAgentThinking from '../AiAgentThinking.vue'

describe('AiAgentThinking', () => {
  it('expands streaming thinking and collapses it when thinking ends', async () => {
    const wrapper = mount(AiAgentThinking, { props: { content: '**Check** facts', running: true } })
    expect(wrapper.get('button').attributes('aria-expanded')).toBe('true')
    expect(wrapper.get('strong').text()).toBe('Check')
    await wrapper.setProps({ running: false })
    expect(wrapper.get('button').attributes('aria-expanded')).toBe('false')
    expect(wrapper.find('.agent-reasoning-content').exists()).toBe(false)
    await wrapper.get('button').trigger('click')
    expect(wrapper.get('.agent-reasoning-content').text()).toBe('Check facts')
  })

  it('preserves a manual toggle while content streams and after completion', async () => {
    const wrapper = mount(AiAgentThinking, { props: { content: 'First', running: true } })
    await wrapper.get('button').trigger('click')
    await wrapper.setProps({ content: 'First second' })
    expect(wrapper.get('button').attributes('aria-expanded')).toBe('false')
    await wrapper.get('button').trigger('click')
    await wrapper.setProps({ running: false })
    expect(wrapper.get('button').attributes('aria-expanded')).toBe('true')
  })
})

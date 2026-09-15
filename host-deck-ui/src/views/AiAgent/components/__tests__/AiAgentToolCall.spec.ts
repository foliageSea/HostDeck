import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import AiAgentToolCall from '../AiAgentToolCall.vue'

const approval = {
  approvalPending: true,
  arguments: { command: 'rm old.log' },
  callId: 'call-1',
  name: 'shell',
  status: 'pending' as const,
  submitting: false,
  summary: 'Remove an old log',
}

describe('AiAgentToolCall', () => {
  it('reveals safe argument text and emits exact approval actions', async () => {
    const wrapper = mount(AiAgentToolCall, {
      props: { tool: approval },
      global: {
        stubs: {
          NButton: { template: '<button type="button"><slot /></button>' },
        },
      },
    })

    expect(wrapper.find('pre').exists()).toBe(false)
    await wrapper.get('.agent-tool-disclosure').trigger('click')
    expect(wrapper.get('pre').text()).toContain('rm old.log')

    const buttons = wrapper.findAll('button')
    await buttons.find((button) => button.text() === '批准')!.trigger('click')
    await buttons.find((button) => button.text() === '拒绝')!.trigger('click')

    expect(wrapper.emitted('approve')).toEqual([['call-1']])
    expect(wrapper.emitted('reject')).toEqual([['call-1']])
  })
})

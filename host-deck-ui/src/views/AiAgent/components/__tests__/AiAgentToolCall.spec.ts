import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import AiAgentToolCall from '../AiAgentToolCall.vue'

const completed = {
  approvalPending: false,
  arguments: { command: 'uptime' },
  callId: 'call-2',
  name: 'shell',
  result: {
    content: 'up 2 days',
    durationMs: 125,
    exitCode: 0,
  },
  status: 'success' as const,
  submitting: false,
  summary: 'Run uptime',
}

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
  it('shows tool arguments and results in a modal', async () => {
    const wrapper = mount(AiAgentToolCall, {
      props: { tool: completed },
      global: {
        stubs: {
          NButton: { template: '<button type="button"><slot /></button>' },
          NModal: {
            props: ['show'],
            template: '<div v-if="show"><slot /></div>',
          },
        },
      },
    })

    expect(wrapper.find('pre').exists()).toBe(false)
    await wrapper.get('.agent-tool-disclosure').trigger('click')
    const outputBlocks = wrapper.findAll('pre')
    expect(outputBlocks[0]?.text()).toContain('uptime')
    expect(outputBlocks[1]?.text()).toContain('up 2 days')
    expect(wrapper.find('.agent-tool-modal-empty').exists()).toBe(false)
  })

  it('reveals safe argument text and emits exact approval actions', async () => {
    const wrapper = mount(AiAgentToolCall, {
      props: { tool: approval },
      global: {
        stubs: {
          NButton: { template: '<button type="button"><slot /></button>' },
          NModal: {
            props: ['show'],
            template: '<div v-if="show"><slot /></div>',
          },
        },
      },
    })

    expect(wrapper.find('pre').exists()).toBe(false)
    await wrapper.get('.agent-tool-disclosure').trigger('click')
    expect(wrapper.get('pre').text()).toContain('rm old.log')

    await wrapper.get('[aria-label="允许一次"]').trigger('click')
    await wrapper.get('[aria-label="拒绝权限申请"]').trigger('click')

    expect(wrapper.emitted('approve')).toEqual([['call-1']])
    expect(wrapper.emitted('reject')).toEqual([['call-1']])
  })
})

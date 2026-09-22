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
  it('opens tool arguments and results when clicking the tool call', async () => {
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

    expect(wrapper.find('.agent-tool-inline-output').exists()).toBe(true)
    await wrapper.get('.agent-tool-heading').trigger('click')
    expect(wrapper.findAll('.agent-tool-arguments')[0]?.text()).toContain('uptime')
    expect(wrapper.findAll('.agent-tool-arguments')[1]?.text()).toContain('up 2 days')
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

    expect(wrapper.find('.agent-approval-preview').exists()).toBe(true)
    await wrapper.get('.agent-approval-detail').trigger('click')
    expect(wrapper.get('pre').text()).toContain('rm old.log')

    await wrapper.get('[aria-label="允许一次"]').trigger('click')
    await wrapper.get('[aria-label="拒绝权限申请"]').trigger('click')

    expect(wrapper.emitted('approve')).toEqual([['call-1']])
    expect(wrapper.emitted('reject')).toEqual([['call-1']])
  })
})

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

  it('offers a full-result action when the inline preview is truncated', async () => {
    const wrapper = mount(AiAgentToolCall, {
      props: {
        tool: {
          ...completed,
          result: {
            ...completed.result,
            content: 'line one\nline two\nline three\nline four',
            structured: { hostname: 'foliage', uptime: '1 week, 1 day' },
          },
        },
      },
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

    expect(wrapper.find('.agent-tool-inline-more').exists()).toBe(true)
    await wrapper.get('.agent-tool-inline-more').trigger('click')
    expect(wrapper.find('.agent-tool-modal-body').exists()).toBe(true)
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

  it('summarizes answered and skipped questions instead of raw JSON', async () => {
    const stubs = {
      NButton: { template: '<button type="button"><slot /></button>' },
      NModal: { props: ['show'], template: '<div v-if="show"><slot /></div>' },
    }
    const base = {
      approvalPending: false,
      questionPending: false,
      callId: 'ask-1',
      name: 'ask_user_question',
      status: 'success' as const,
      submitting: false,
      summary: 'Ask the user a question',
      arguments: { questions: [{ question: 'Where?', options: [] }] },
    }
    const answered = mount(AiAgentToolCall, {
      props: {
        tool: {
          ...base,
          result: {
            content: '{}',
            questionStatus: 'answered',
            answers: [{ id: 'q1', selected: ['Staging'], custom: 'and canary' }],
          },
        },
      },
      global: { stubs },
    })
    expect(answered.get('.agent-tool-label').text()).toBe('已回答')
    expect(answered.get('.agent-tool-inline-output').text()).toBe('Where?\n→ Staging、and canary')

    const skipped = mount(AiAgentToolCall, {
      props: {
        tool: { ...base, result: { content: '{}', questionStatus: 'skipped', answers: [] } },
      },
      global: { stubs },
    })
    expect(skipped.get('.agent-tool-label').text()).toBe('已跳过')
    expect(skipped.get('.agent-tool-inline-output').text()).toBe('你跳过了这些问题。')

    const waiting = mount(AiAgentToolCall, {
      props: { tool: { ...base, status: 'pending' as const, questionPending: true } },
      global: { stubs },
    })
    expect(waiting.get('.agent-tool-label').text()).toBe('等待回答')
  })
})

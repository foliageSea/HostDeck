import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import type { AiAgentQuestion } from '@/api/ai-agent'
import AiAgentQuestionPanel from '../AiAgentQuestionPanel.vue'

const NButtonStub = {
  props: ['disabled', 'loading'],
  template: '<button type="button" :disabled="disabled"><slot /></button>',
}

const questions: AiAgentQuestion[] = [
  {
    id: 'env',
    header: '部署环境',
    question: '要部署到哪个环境？',
    multiSelect: false,
    options: [
      { label: '测试环境', description: '较安全', recommended: true },
      { label: '生产环境' },
    ],
  },
  {
    id: 'fruit',
    question: '选择水果',
    multiSelect: true,
    options: [{ label: '苹果' }, { label: '香蕉' }],
  },
]

function mountPanel(items = questions) {
  return mount(AiAgentQuestionPanel, {
    props: { questions: items },
    attachTo: document.body,
    global: { stubs: { NButton: NButtonStub } },
  })
}

function nextButton(wrapper: ReturnType<typeof mountPanel>) {
  return wrapper.findAll('.agent-question-actions button')[1]!
}

describe('AiAgentQuestionPanel', () => {
  it('renders the question, recommended tag and the free-form row', () => {
    const wrapper = mountPanel()
    expect(wrapper.text()).toContain('部署环境')
    expect(wrapper.text()).toContain('要部署到哪个环境？')
    expect(wrapper.get('.agent-question-tag').text()).toBe('推荐')
    expect(wrapper.find('input.agent-question-input').exists()).toBe(true)
    expect(wrapper.get('.agent-question-count').text()).toBe('1 / 2')
    wrapper.unmount()
  })

  it('walks through the questions and submits one answer per question', async () => {
    const wrapper = mountPanel()
    expect(nextButton(wrapper).attributes('disabled')).toBeDefined()

    await wrapper.findAll('.agent-question-option')[0]!.trigger('click')
    expect(nextButton(wrapper).text()).toBe('下一题')
    await nextButton(wrapper).trigger('click')

    expect(wrapper.get('.agent-question-count').text()).toBe('2 / 2')
    expect(wrapper.findAll('.agent-question-box')).toHaveLength(3)
    expect(nextButton(wrapper).text()).toBe('提交')
    await wrapper.findAll('.agent-question-option')[0]!.trigger('click')
    await wrapper.findAll('.agent-question-option')[1]!.trigger('click')
    await wrapper.get('input.agent-question-input').setValue('  橙子  ')
    await nextButton(wrapper).trigger('click')

    expect(wrapper.emitted('submit')).toEqual([
      [
        [
          { id: 'env', selected: ['测试环境'] },
          { id: 'fruit', selected: ['苹果', '香蕉'], custom: '橙子' },
        ],
      ],
    ])
    wrapper.unmount()
  })

  it('keeps single-select answers exclusive between options and typed text', async () => {
    const wrapper = mountPanel()
    await wrapper.findAll('.agent-question-option')[0]!.trigger('click')
    await wrapper.get('input.agent-question-input').setValue('自定义')
    expect(wrapper.findAll('.agent-question-option-selected')).toHaveLength(0)

    await wrapper.findAll('.agent-question-option')[1]!.trigger('click')
    expect((wrapper.get('input.agent-question-input').element as HTMLInputElement).value).toBe('')
    wrapper.unmount()
  })

  it('selects options with number keys and advances with Enter', async () => {
    const wrapper = mountPanel()
    document.body.dispatchEvent(new KeyboardEvent('keydown', { key: '2', bubbles: true }))
    await wrapper.vm.$nextTick()
    expect(wrapper.findAll('.agent-question-option')[1]!.classes()).toContain(
      'agent-question-option-selected',
    )
    document.body.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))
    await wrapper.vm.$nextTick()
    expect(wrapper.get('.agent-question-count').text()).toBe('2 / 2')
    wrapper.unmount()
  })

  it('emits skip from the close button and the skip action', async () => {
    const wrapper = mountPanel()
    await wrapper.get('button[aria-label="跳过提问"]').trigger('click')
    await wrapper.findAll('.agent-question-actions button')[0]!.trigger('click')
    expect(wrapper.emitted('skip')).toHaveLength(2)
    wrapper.unmount()
  })

  it('collapses to the heading only', async () => {
    const wrapper = mountPanel()
    await wrapper.get('button[aria-label="收起问题"]').trigger('click')
    expect(wrapper.find('.agent-question-options').exists()).toBe(false)
    expect(wrapper.text()).toContain('要部署到哪个环境？')
    wrapper.unmount()
  })
})

import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { defineComponent } from 'vue'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useAiAgentStore } from '@/stores/ai-agent'
import { useDesktopStore } from '@/stores/desktop'
import AiAgentView from '../index.vue'

const apiMocks = vi.hoisted(() => ({
  cancel: vi.fn().mockResolvedValue(undefined),
  closeSession: vi.fn().mockResolvedValue(undefined),
  getSettings: vi.fn().mockResolvedValue(null),
  listConversations: vi.fn().mockResolvedValue([]),
  listMcpServers: vi.fn().mockResolvedValue([]),
  listSkills: vi.fn().mockResolvedValue([]),
  modelCatalog: vi.fn().mockResolvedValue([]),
}))

vi.mock('@/api/ai-agent', () => ({ aiAgentApi: apiMocks }))

const PassthroughStub = defineComponent({ template: '<div><slot /><slot name="trigger" /></div>' })
const MentionStub = defineComponent({
  props: { value: { type: String, default: '' } },
  emits: ['update:value'],
  template: '<textarea class="agent-composer-input" :value="value" />',
})
const ImageStub = defineComponent({ template: '<span />' })
const SpinStub = defineComponent({ template: '<span />' })

function mountView() {
  const windowId = useDesktopStore().openWindow('ai-agent')!
  const wrapper = mount(AiAgentView, {
    props: { windowId },
    attachTo: document.body,
    global: {
      stubs: {
        AiAgentMarkdown: true,
        AiAgentSkillPicker: true,
        AiAgentModelPicker: true,
        AiAgentToolCall: true,
        NImage: ImageStub,
        NMention: MentionStub,
        NPopover: PassthroughStub,
        NSpin: SpinStub,
      },
    },
  })
  return wrapper
}

function pressEscape(target: EventTarget) {
  target.dispatchEvent(
    new KeyboardEvent('keydown', {
      bubbles: true,
      cancelable: true,
      code: 'Escape',
      key: 'Escape',
    }),
  )
}

describe('AiAgent escape', () => {
  beforeEach(() => {
    document.body.innerHTML = ''
    setActivePinia(createPinia())
    vi.clearAllMocks()
    window.localStorage.clear()
    Object.defineProperty(window, 'matchMedia', {
      configurable: true,
      value: vi.fn().mockReturnValue({
        addEventListener: vi.fn(),
        matches: false,
        removeEventListener: vi.fn(),
      }),
    })
  })

  it('cancels the running agent on Escape', async () => {
    const store = useAiAgentStore()
    const cancelRun = vi.spyOn(store, 'cancelRun').mockResolvedValue(undefined)

    const wrapper = mountView()
    ;(store as unknown as { running: boolean }).running = true
    await wrapper.vm.$nextTick()

    pressEscape(wrapper.element)
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(cancelRun).toHaveBeenCalledTimes(1)
    wrapper.unmount()
  })

  it('still cancels after a modal container has been left in the DOM', async () => {
    const store = useAiAgentStore()
    const cancelRun = vi.spyOn(store, 'cancelRun').mockResolvedValue(undefined)

    // naive-ui 的 LazyTeleport 关闭弹窗后仍保留容器节点
    const stale = document.createElement('div')
    stale.className = 'n-modal-container'
    document.body.appendChild(stale)

    const wrapper = mountView()
    ;(store as unknown as { running: boolean }).running = true
    await wrapper.vm.$nextTick()

    pressEscape(wrapper.element)
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(cancelRun).toHaveBeenCalledTimes(1)
    wrapper.unmount()
  })

  it('lets an open modal handle Escape itself', async () => {
    const store = useAiAgentStore()
    const cancelRun = vi.spyOn(store, 'cancelRun').mockResolvedValue(undefined)

    const container = document.createElement('div')
    container.className = 'n-modal-container'
    const modal = document.createElement('div')
    modal.className = 'n-modal'
    container.appendChild(modal)
    document.body.appendChild(container)

    const wrapper = mountView()
    ;(store as unknown as { running: boolean }).running = true
    await wrapper.vm.$nextTick()

    pressEscape(wrapper.element)
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(cancelRun).not.toHaveBeenCalled()
    wrapper.unmount()
  })

  it('does nothing when the agent is idle', async () => {
    const store = useAiAgentStore()
    const cancelRun = vi.spyOn(store, 'cancelRun').mockResolvedValue(undefined)

    const wrapper = mountView()
    pressEscape(wrapper.element)
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(cancelRun).not.toHaveBeenCalled()
    wrapper.unmount()
  })

  it('renders pre-tool thinking and commentary before the tool and final answer', async () => {
    const store = useAiAgentStore()
    const wrapper = mountView()
    await new Promise((resolve) => setTimeout(resolve, 0))
    store.messages = [
      { id: 'user', role: 'user', content: '当前 docker 情况', attachments: [], createdAt: 1 },
      {
        id: 'answer',
        role: 'assistant',
        content: 'Docker is healthy.',
        attachments: [],
        createdAt: 4,
      },
    ]
    store.runSteps = [
      {
        runId: 'run',
        stepId: 'before',
        messageId: 'answer',
        sequence: 1,
        type: 'model',
        status: 'success',
        startedAt: 2,
        content: 'I will inspect Docker.',
        thinking: 'Check containers first.',
      },
      {
        runId: 'run',
        stepId: 'tool',
        callId: 'call',
        sequence: 2,
        type: 'tool',
        status: 'success',
        startedAt: 3,
      },
      {
        runId: 'run',
        stepId: 'after',
        messageId: 'answer',
        sequence: 3,
        type: 'model',
        status: 'success',
        startedAt: 4,
        content: 'Docker is healthy.',
      },
    ]
    store.toolCalls = [
      {
        callId: 'call',
        name: 'shell_execute',
        summary: 'Inspect Docker',
        status: 'success',
        approvalPending: false,
        submitting: false,
      },
    ]
    await wrapper.vm.$nextTick()
    const transcript = wrapper.get('.agent-transcript')
    const blocks = transcript.findAll('.agent-message, .agent-tools')
    expect(blocks).toHaveLength(4)
    expect(blocks[1]!.get('button.agent-reasoning-toggle').text()).toBe('思考过程')
    await blocks[1]!.get('button.agent-reasoning-toggle').trigger('click')
    expect(
      blocks[1]!.findAll('ai-agent-markdown-stub').map((node) => node.attributes('content')),
    ).toEqual(['Check containers first.', 'I will inspect Docker.'])
    expect(blocks[2]!.find('ai-agent-tool-call-stub').exists()).toBe(true)
    expect(blocks[3]!.get('ai-agent-markdown-stub').attributes('content')).toBe(
      'Docker is healthy.',
    )
    wrapper.unmount()
  })
})

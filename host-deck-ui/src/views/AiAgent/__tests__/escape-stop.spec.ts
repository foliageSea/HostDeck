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
        AiAgentThinkingPicker: true,
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
})

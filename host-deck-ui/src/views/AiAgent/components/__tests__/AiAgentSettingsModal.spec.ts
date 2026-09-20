import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { defineComponent } from 'vue'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useAiAgentStore } from '@/stores/ai-agent'
import AiAgentSettingsModal from '../AiAgentSettingsModal.vue'

const apiMocks = vi.hoisted(() => ({
  getSettings: vi.fn(),
  saveSettings: vi.fn(),
}))

const uiMocks = vi.hoisted(() => ({
  message: {
    error: vi.fn(),
    info: vi.fn(),
    success: vi.fn(),
    warning: vi.fn(),
  },
}))

vi.mock('@/api/ai-agent', () => ({ aiAgentApi: apiMocks }))
vi.mock('@/lib/ui', () => ({ getUiApi: () => uiMocks }))

const settings = {
  baseUrl: 'https://api.example.com/v1',
  hasApiKey: true,
  model: 'model-a',
  models: [{ id: 'model-a', name: 'Model A' }],
  showRemoteSkills: false,
}

function mountModal() {
  return mount(AiAgentSettingsModal, {
    props: { show: true },
    global: {
      stubs: {
        AiAgentMcpSettings: { template: '<div />' },
        AiAgentSkillSettings: { template: '<div />' },
        NButton: {
          props: ['disabled', 'loading'],
          emits: ['click'],
          template:
            '<button type="button" :disabled="disabled" @click="$emit(\'click\', $event)"><slot /></button>',
        },
        NForm: { template: '<form><slot /></form>' },
        NFormItem: { template: '<div><slot /></div>' },
        NInput: {
          props: ['value'],
          emits: ['update:value'],
          template:
            '<input :value="value" @input="$emit(\'update:value\', $event.target.value)" />',
        },
        NModal: {
          props: ['show'],
          template: '<div v-if="show"><slot /><slot name="footer" /></div>',
        },
        NSelect: { template: '<select />' },
        NSwitch: {
          props: ['value'],
          emits: ['update:value'],
          template: '<input type="checkbox" :checked="value" />',
        },
        NTabPane: { template: '<div><slot /></div>' },
        NTabs: defineComponent({ template: '<div><slot /></div>' }),
      },
    },
  })
}

function getSaveButton(wrapper: ReturnType<typeof mountModal>) {
  return wrapper.findAll('button').find((button) => button.text() === '保存')
}

describe('AiAgentSettingsModal', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
    const store = useAiAgentStore()
    store.settings = { ...settings, models: settings.models.map((model) => ({ ...model })) }
  })

  it('skips saving when settings are unchanged', async () => {
    const wrapper = mountModal()
    await flushPromises()

    await getSaveButton(wrapper)?.trigger('click')

    expect(apiMocks.saveSettings).not.toHaveBeenCalled()
    expect(uiMocks.message.info).not.toHaveBeenCalled()
    expect(wrapper.emitted('update:show')).toEqual([[false]])
  })

  it('saves changed settings only once while a save is pending', async () => {
    let resolveSave!: (value: typeof settings) => void
    apiMocks.saveSettings.mockReturnValue(
      new Promise((resolve) => {
        resolveSave = resolve
      }),
    )
    const wrapper = mountModal()
    await flushPromises()
    await wrapper.findAll('input')[0]!.setValue('https://api.example.com/v2')

    const saveButton = getSaveButton(wrapper)
    await saveButton?.trigger('click')
    await saveButton?.trigger('click')

    expect(apiMocks.saveSettings).toHaveBeenCalledTimes(1)
    resolveSave({ ...settings, baseUrl: 'https://api.example.com/v2' })
    await flushPromises()
    expect(apiMocks.saveSettings).toHaveBeenCalledTimes(1)
    expect(wrapper.emitted('update:show')).toEqual([[false]])
  })
})

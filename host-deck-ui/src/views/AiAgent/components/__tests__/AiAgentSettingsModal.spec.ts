import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { defineComponent } from 'vue'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useAiAgentStore } from '@/stores/ai-agent'
import AiAgentSettingsModal from '../AiAgentSettingsModal.vue'

const apiMocks = vi.hoisted(() => ({
  getSettings: vi.fn(),
  saveSettings: vi.fn(),
  modelCatalog: vi.fn().mockResolvedValue([]),
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
  provider: 'custom',
  api: 'openai-completions',
  baseUrl: 'https://api.example.com/v1',
  hasApiKey: true,
  hasOAuth: false,
  hasCredentials: true,
  model: 'model-a',
  models: [{ id: 'model-a', name: 'Model A' }],
  providers: [
    {
      id: 'custom',
      api: 'openai-completions',
      baseUrl: 'https://api.example.com/v1',
      model: 'model-a',
      models: [{ id: 'model-a', name: 'Model A' }],
      hasApiKey: true,
      hasOAuth: false,
      hasCredentials: true,
    },
  ],
  showRemoteSkills: false,
}

function mountModal() {
  return mount(AiAgentSettingsModal, {
    props: { show: true },
    global: {
      stubs: {
        AiAgentOAuthLogin: { template: '<div />' },
        NAlert: { template: '<div><slot /></div>' },
        AiAgentMcpSettings: { template: '<div />' },
        AiAgentSkillSettings: { template: '<div />' },
        AiAgentToolList: { template: '<div />' },
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
        NSelect: {
          name: 'NSelect',
          props: ['options', 'value', 'tag'],
          template: '<select :data-tag="tag ? \'true\' : \'false\'" />',
        },
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
    store.settings = structuredClone(settings)
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

  it('restores and activates an independently configured provider', async () => {
    const store = useAiAgentStore()
    const anthropic = {
      id: 'anthropic',
      api: 'anthropic-messages',
      baseUrl: 'https://api.anthropic.com',
      model: 'claude-test',
      models: [{ id: 'claude-test', name: 'Claude Test' }],
      hasApiKey: true,
      hasOAuth: false,
      hasCredentials: true,
    }
    store.settings!.providers.push(anthropic)
    apiMocks.saveSettings.mockResolvedValue({
      ...structuredClone(settings),
      provider: anthropic.id,
      api: anthropic.api,
      baseUrl: anthropic.baseUrl,
      model: anthropic.model,
      models: anthropic.models,
      providers: [...store.settings!.providers],
    })
    const wrapper = mountModal()
    await flushPromises()
    ;(wrapper.vm as unknown as { selectProvider: (provider: string) => void }).selectProvider(
      'anthropic',
    )
    await getSaveButton(wrapper)?.trigger('click')
    await flushPromises()

    expect(apiMocks.saveSettings).toHaveBeenCalledWith(
      expect.objectContaining({
        provider: 'anthropic',
        api: 'anthropic-messages',
        baseUrl: 'https://api.anthropic.com',
        model: 'claude-test',
      }),
    )
    expect(apiMocks.saveSettings.mock.calls[0]![0]).not.toHaveProperty('apiKey')
  })

  it('allows custom model IDs for catalog providers', async () => {
    const store = useAiAgentStore()
    store.settings!.providers.push({
      id: 'openai',
      api: 'openai-responses',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-5',
      models: [{ id: 'gpt-5', name: 'GPT-5' }],
      hasApiKey: true,
      hasOAuth: false,
      hasCredentials: true,
    })
    const wrapper = mountModal()
    await flushPromises()
    const component = wrapper.vm as unknown as {
      selectProvider: (provider: string) => void
      updateModelId: (index: number, id: string) => void
    }
    component.selectProvider('openai')
    component.updateModelId(0, 'company-preview-model')
    apiMocks.saveSettings.mockResolvedValue({
      ...structuredClone(settings),
      provider: 'openai',
      api: 'openai-responses',
      baseUrl: 'https://api.openai.com/v1',
      model: 'company-preview-model',
      models: [{ id: 'company-preview-model', name: 'company-preview-model' }],
    })
    await getSaveButton(wrapper)?.trigger('click')
    await flushPromises()
    expect(apiMocks.saveSettings).toHaveBeenCalledWith(
      expect.objectContaining({
        provider: 'openai',
        model: 'company-preview-model',
        models: [{ id: 'company-preview-model', name: 'company-preview-model' }],
      }),
    )
  })
})

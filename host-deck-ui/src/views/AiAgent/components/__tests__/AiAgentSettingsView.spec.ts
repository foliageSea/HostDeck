import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { defineComponent } from 'vue'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useAiAgentStore } from '@/stores/ai-agent'
import AiAgentSettingsView from '../AiAgentSettingsView.vue'

const apiMocks = vi.hoisted(() => ({
  getSettings: vi.fn(),
  saveSettings: vi.fn(),
  saveProvider: vi.fn(),
  deleteProvider: vi.fn(),
  activateModel: vi.fn(),
  modelCatalog: vi.fn().mockResolvedValue([]),
}))

const uiMocks = vi.hoisted(() => ({
  message: {
    error: vi.fn(),
    info: vi.fn(),
    success: vi.fn(),
    warning: vi.fn(),
  },
  dialog: {
    warning: vi.fn((_options: unknown) => ({ loading: false })),
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

const anthropicProvider = {
  id: 'anthropic',
  api: 'anthropic-messages',
  baseUrl: 'https://api.anthropic.com',
  model: 'claude-test',
  models: [{ id: 'claude-test', name: 'Claude Test' }],
  hasApiKey: true,
  hasOAuth: false,
  hasCredentials: true,
}

function mountView() {
  return mount(AiAgentSettingsView, {
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
          template: "<select :data-tag=\"tag ? 'true' : 'false'\" />",
        },
        NSwitch: {
          props: ['value'],
          emits: ['update:value'],
          template:
            '<input type="checkbox" :checked="value" @change="$emit(\'update:value\', $event.target.checked)" />',
        },
        NTabPane: { template: '<div><slot /></div>' },
        NTabs: defineComponent({ template: '<div><slot /></div>' }),
      },
    },
  })
}

function getButton(wrapper: ReturnType<typeof mountView>, text: string) {
  return wrapper.findAll('button').find((button) => button.text() === text)
}

function getNotificationSwitch(wrapper: ReturnType<typeof mountView>, label: string) {
  return wrapper
    .findAll('.agent-notification-row')
    .find((row) => row.text().includes(label))
    ?.find('input[type="checkbox"]')
}

describe('AiAgentSettingsView', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
    const store = useAiAgentStore()
    store.settings = structuredClone(settings)
  })

  it('disables saving while the selected provider is unchanged', async () => {
    const wrapper = mountView()
    await flushPromises()

    expect(getButton(wrapper, '保存')?.attributes('disabled')).toBeDefined()
    expect(apiMocks.saveProvider).not.toHaveBeenCalled()
    expect(apiMocks.saveSettings).not.toHaveBeenCalled()
  })

  it('saves changed settings only once while a save is pending', async () => {
    let resolveSave!: (value: typeof settings) => void
    apiMocks.saveProvider.mockReturnValue(
      new Promise((resolve) => {
        resolveSave = resolve
      }),
    )
    const wrapper = mountView()
    await flushPromises()
    await wrapper.find('.provider-detail input').setValue('https://api.example.com/v2')

    const saveButton = getButton(wrapper, '保存')
    await saveButton?.trigger('click')
    await saveButton?.trigger('click')

    expect(apiMocks.saveProvider).toHaveBeenCalledTimes(1)
    expect(apiMocks.saveProvider).toHaveBeenCalledWith(
      'custom',
      expect.objectContaining({ baseUrl: 'https://api.example.com/v2' }),
    )
    resolveSave({ ...structuredClone(settings), baseUrl: 'https://api.example.com/v2' })
    await flushPromises()
    expect(apiMocks.saveProvider).toHaveBeenCalledTimes(1)
  })

  it('restores an independently configured provider and activates it separately', async () => {
    const store = useAiAgentStore()
    store.settings!.providers.push({ ...anthropicProvider })
    apiMocks.activateModel.mockResolvedValue({
      ...structuredClone(settings),
      provider: anthropicProvider.id,
      api: anthropicProvider.api,
      baseUrl: anthropicProvider.baseUrl,
      model: anthropicProvider.model,
      models: anthropicProvider.models,
    })
    const wrapper = mountView()
    await flushPromises()
    ;(wrapper.vm as unknown as { selectProvider: (provider: string) => void }).selectProvider(
      'anthropic',
    )
    await wrapper.vm.$nextTick()

    expect(getButton(wrapper, '保存')?.attributes('disabled')).toBeDefined()
    await getButton(wrapper, '设为当前')?.trigger('click')
    await flushPromises()

    expect(apiMocks.activateModel).toHaveBeenCalledWith({
      provider: 'anthropic',
      model: 'claude-test',
    })
    expect(apiMocks.saveProvider).not.toHaveBeenCalled()
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
    const wrapper = mountView()
    await flushPromises()
    const component = wrapper.vm as unknown as {
      selectProvider: (provider: string) => void
      updateModelId: (index: number, id: string) => void
    }
    component.selectProvider('openai')
    component.updateModelId(0, 'company-preview-model')
    await wrapper.vm.$nextTick()
    apiMocks.saveProvider.mockResolvedValue(structuredClone(settings))
    await getButton(wrapper, '保存')?.trigger('click')
    await flushPromises()
    expect(apiMocks.saveProvider).toHaveBeenCalledWith(
      'openai',
      expect.objectContaining({
        model: 'company-preview-model',
        models: [{ id: 'company-preview-model', name: 'company-preview-model' }],
      }),
    )
  })

  it('deletes a non-active provider after confirmation', async () => {
    const store = useAiAgentStore()
    store.settings!.providers.push({ ...anthropicProvider })
    apiMocks.deleteProvider.mockResolvedValue(structuredClone(settings))
    const wrapper = mountView()
    await flushPromises()
    ;(wrapper.vm as unknown as { selectProvider: (provider: string) => void }).selectProvider(
      'anthropic',
    )
    await wrapper.vm.$nextTick()

    await wrapper.find('button[aria-label="删除配置"]').trigger('click')
    expect(uiMocks.dialog.warning).toHaveBeenCalled()
    const dialog = uiMocks.dialog.warning.mock.results[0]!.value as { loading: boolean }
    const options = uiMocks.dialog.warning.mock.calls[0]![0] as unknown as {
      onPositiveClick: () => Promise<void>
    }
    await options.onPositiveClick()

    expect(apiMocks.deleteProvider).toHaveBeenCalledWith('anthropic')
    expect(dialog.loading).toBe(false)
  })

  it('does not offer deletion for the active provider', async () => {
    const wrapper = mountView()
    await flushPromises()
    expect(wrapper.find('button[aria-label="删除配置"]').exists()).toBe(false)
    expect(getButton(wrapper, '设为当前')).toBeUndefined()
  })

  it('selects a new provider from the add-provider modal', async () => {
    apiMocks.modelCatalog.mockResolvedValue([
      {
        id: 'anthropic',
        name: 'Anthropic',
        models: [anthropicProvider.models[0]],
      },
    ])
    const wrapper = mountView()
    await flushPromises()

    await getButton(wrapper, '添加供应商')?.trigger('click')
    expect(wrapper.find('.provider-picker-modal').exists()).toBe(true)

    await wrapper.get('.provider-picker-item').trigger('click')
    expect(wrapper.find('.provider-detail-heading').text()).toContain('Anthropic')
    expect(wrapper.find('.provider-item-draft').exists()).toBe(true)
  })

  it('asks before switching sections when provider changes are unsaved', async () => {
    const wrapper = mountView()
    await flushPromises()
    await wrapper.find('.provider-detail input').setValue('https://api.example.com/v2')

    await wrapper.setProps({ initialTab: 'tools', tabRequestId: 1 })

    expect(uiMocks.dialog.warning).toHaveBeenCalledOnce()
    const options = uiMocks.dialog.warning.mock.calls[0]![0] as unknown as {
      onPositiveClick: () => void
    }
    options.onPositiveClick()
    await wrapper.vm.$nextTick()
    expect((wrapper.vm as unknown as { activeTab: string }).activeTab).toBe('tools')
  })

  it('renders the notification switches from the stored preferences', async () => {
    const store = useAiAgentStore()
    store.notificationPreferences = { question: false, runComplete: true }
    const wrapper = mountView()
    await flushPromises()

    expect(getNotificationSwitch(wrapper, '任务完成时通知')?.element).toHaveProperty(
      'checked',
      true,
    )
    expect(getNotificationSwitch(wrapper, 'Agent 提问时通知')?.element).toHaveProperty(
      'checked',
      false,
    )
  })

  it('applies notification switches immediately instead of waiting for a save', async () => {
    const store = useAiAgentStore()
    const setPreference = vi.spyOn(store, 'setNotificationPreference')
    const wrapper = mountView()
    await flushPromises()

    await getNotificationSwitch(wrapper, '任务完成时通知')?.setValue(false)
    await getNotificationSwitch(wrapper, 'Agent 提问时通知')?.setValue(false)

    expect(setPreference).toHaveBeenCalledWith('runComplete', false)
    expect(setPreference).toHaveBeenCalledWith('question', false)
  })

  it('requests notification permission when the browser has not decided yet', async () => {
    const store = useAiAgentStore()
    store.notificationPermission = 'default'
    const requestAccess = vi.spyOn(store, 'requestNotificationAccess').mockResolvedValue('granted')
    const wrapper = mountView()
    await flushPromises()

    const allowButton = getButton(wrapper, '允许通知')
    expect(allowButton).toBeDefined()
    await allowButton?.trigger('click')
    await flushPromises()

    expect(requestAccess).toHaveBeenCalledOnce()
  })

  it('confirms a granted notification permission', async () => {
    const store = useAiAgentStore()
    store.notificationPermission = 'granted'
    const wrapper = mountView()
    await flushPromises()

    expect(wrapper.text()).toContain('浏览器通知已授权')
    expect(getButton(wrapper, '允许通知')).toBeUndefined()
  })

  it('explains how to recover from a denied notification permission', async () => {
    const store = useAiAgentStore()
    store.notificationPermission = 'denied'
    const wrapper = mountView()
    await flushPromises()

    expect(wrapper.text()).toContain('浏览器已拒绝通知权限，请在浏览器的站点设置中重新允许')
    expect(getButton(wrapper, '允许通知')).toBeUndefined()
  })

  it('reports environments without browser notification support', async () => {
    const store = useAiAgentStore()
    store.notificationPermission = 'unsupported'
    const wrapper = mountView()
    await flushPromises()

    expect(wrapper.text()).toContain('当前环境不支持浏览器通知（需要 HTTPS 或 localhost）')
    expect(getButton(wrapper, '允许通知')).toBeUndefined()
  })

  it('refreshes the permission state when the notifications tab opens', async () => {
    const store = useAiAgentStore()
    const refresh = vi.spyOn(store, 'refreshNotificationPermission')
    const wrapper = mountView()
    await flushPromises()

    await wrapper.setProps({ initialTab: 'notifications', tabRequestId: 1 })
    await flushPromises()

    expect(refresh).toHaveBeenCalledOnce()
    expect((wrapper.vm as unknown as { activeTab: string }).activeTab).toBe('notifications')
  })
})

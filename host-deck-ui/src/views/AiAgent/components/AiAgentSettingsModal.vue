<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import {
  CheckCircle2,
  ChevronDown,
  KeyRound,
  Plus,
  RefreshCw,
  RotateCcw,
  Trash2,
  TriangleAlert,
} from '@lucide/vue'
import {
  aiAgentApi,
  type AiAgentModelConfig,
  type AiAgentProviderCatalog,
  type AiAgentProviderUpdate,
} from '@/api/ai-agent'
import { getUiApi } from '@/lib/ui'
import { useAiAgentStore } from '@/stores/ai-agent'
import AiAgentMcpSettings from './AiAgentMcpSettings.vue'
import AiAgentSkillSettings from './AiAgentSkillSettings.vue'
import AiAgentToolList from './AiAgentToolList.vue'
import AiAgentOAuthLogin from './AiAgentOAuthLogin.vue'

const props = defineProps<{
  show: boolean
  initialTab?: 'mcp' | 'model' | 'skills' | 'tools'
}>()

const emit = defineEmits<{
  'update:show': [value: boolean]
}>()

const store = useAiAgentStore()
const skillSettings = ref<InstanceType<typeof AiAgentSkillSettings> | null>(null)
const saving = ref(false)
const testing = ref(false)
const activating = ref(false)
const deleting = ref(false)
const loadingModels = ref(false)
const advancedOpen = ref(false)
const activeTab = ref<'mcp' | 'model' | 'skills' | 'tools'>('model')

const form = reactive({
  provider: 'custom',
  api: 'openai-completions',
  baseUrl: '',
  model: '',
  models: [] as AiAgentModelConfig[],
  apiKey: '',
})
const availableModels = ref<string[]>([])
const providers = ref<AiAgentProviderCatalog[]>([])
const catalogError = ref('')

const apiOptions = [
  { label: 'OpenAI Chat Completions', value: 'openai-completions' },
  { label: 'OpenAI Responses', value: 'openai-responses' },
  { label: 'Anthropic Messages', value: 'anthropic-messages' },
  { label: 'Google Gemini', value: 'google-generative-ai' },
]

function providerDisplayName(id: string) {
  if (id === 'custom') return '自定义 / OpenAI 兼容'
  const catalog = providers.value.find((provider) => provider.id === id)
  return catalog?.name || catalog?.id || id
}

const configuredProviders = computed(() => store.settings?.providers ?? [])
const savedProvider = computed(() =>
  configuredProviders.value.find((provider) => provider.id === form.provider),
)
const isDraftProvider = computed(() => !savedProvider.value)
const isActiveProvider = computed(() => form.provider === store.settings?.provider)
const addableProviderOptions = computed(() => {
  const configured = new Set(configuredProviders.value.map((provider) => provider.id))
  const options = providers.value
    .filter((provider) => !configured.has(provider.id))
    .map((provider) => ({ label: provider.name || provider.id, value: provider.id }))
  if (!configured.has('custom')) {
    options.unshift({ label: providerDisplayName('custom'), value: 'custom' })
  }
  return options
})

const providerModels = computed(
  () => providers.value.find((item) => item.id === form.provider)?.models ?? [],
)
const usesPlainHttp = computed(() => /^http:\/\//i.test(form.baseUrl.trim()))
const modelOptions = computed(() =>
  (form.provider === 'custom'
    ? availableModels.value
    : providerModels.value.map((model) => model.id)
  ).map((model) => ({
    label: model,
    value: model,
  })),
)
const selectedModelOptions = computed(() =>
  form.models
    .filter((model) => model.id.trim())
    .map((model) => ({ label: model.name.trim() || model.id, value: model.id })),
)

function normalizedModels(models: AiAgentModelConfig[]) {
  return models
    .map((model) => ({ id: model.id.trim(), name: model.name.trim() }))
    .filter((model) => model.id || model.name)
    .sort((a, b) => a.id.localeCompare(b.id))
}

const dirty = computed(() => {
  if (form.apiKey.trim()) return true
  const saved = savedProvider.value
  if (!saved) return true
  if (form.api !== saved.api || form.baseUrl.trim() !== saved.baseUrl) return true
  if (form.model.trim() !== saved.model) return true
  const next = normalizedModels(form.models)
  const current = normalizedModels(saved.models)
  return (
    next.length !== current.length ||
    next.some((model, index) => {
      const savedModel = current[index]
      return model.id !== savedModel?.id || model.name !== savedModel?.name
    })
  )
})

function confirmDiscardingForm(action: () => void) {
  if (activeTab.value !== 'model' || !dirty.value) {
    action()
    return
  }
  getUiApi().dialog.warning({
    title: '放弃未保存的修改',
    content: `供应商「${providerDisplayName(form.provider)}」的配置尚未保存，确认放弃修改？`,
    positiveText: '放弃修改',
    negativeText: '继续编辑',
    onPositiveClick: action,
  })
}

function confirmLeavingSkills(action: () => void) {
  if (activeTab.value !== 'skills' || !skillSettings.value?.dirty) {
    confirmDiscardingForm(action)
    return
  }
  getUiApi().dialog.warning({
    title: '放弃未保存的修改',
    content: '当前 SKILL.md 尚未保存，确认放弃修改？',
    positiveText: '放弃修改',
    negativeText: '继续编辑',
    onPositiveClick: action,
  })
}

function changeTab(value: string | number) {
  confirmLeavingSkills(() => {
    activeTab.value = value as 'model' | 'mcp' | 'skills' | 'tools'
  })
}

function changeVisibility(value: boolean) {
  if (value) return emit('update:show', true)
  confirmLeavingSkills(() => emit('update:show', false))
}

function selectProvider(provider: string) {
  form.provider = provider
  availableModels.value = []
  form.apiKey = ''
  advancedOpen.value = provider === 'custom'
  const saved = store.settings?.providers.find((item) => item.id === provider)
  if (saved) {
    form.api = saved.api
    form.baseUrl = saved.baseUrl
    form.model = saved.model
    form.models = saved.models.map((model) => ({ ...model }))
    return
  }
  if (provider === 'custom') {
    form.api = 'openai-completions'
    form.baseUrl = 'https://api.openai.com/v1'
    form.model = 'gpt-4o-mini'
    form.models = [{ id: form.model, name: form.model }]
    return
  }
  const first = providerModels.value[0]
  if (first) {
    form.api = first.api
    form.baseUrl = first.baseUrl
    form.model = first.id
    form.models = [{ id: first.id, name: first.name }]
  }
}

function chooseProvider(provider: string) {
  if (provider === form.provider) return
  confirmDiscardingForm(() => selectProvider(provider))
}

function syncForm() {
  selectProvider(store.settings?.provider ?? 'custom')
}

watch(
  () => props.show,
  async (show) => {
    if (!show) return
    activeTab.value = props.initialTab ?? 'model'
    try {
      if (!store.settings) await store.loadSettings()
      catalogError.value = ''
      try {
        providers.value = await aiAgentApi.modelCatalog()
      } catch (error) {
        catalogError.value = error instanceof Error ? error.message : '无法加载 pi-ai 模型目录。'
      }
      syncForm()
    } catch (error) {
      getUiApi().message.error(error instanceof Error ? error.message : '加载 AI 设置失败。')
    }
  },
  { immediate: true },
)

function payload(): AiAgentProviderUpdate {
  const apiKey = form.apiKey.trim()
  return {
    api: form.api,
    baseUrl: form.baseUrl.trim(),
    model: form.model.trim(),
    models: normalizedModels(form.models),
    ...(apiKey ? { apiKey } : {}),
  }
}

function addModel() {
  form.models.push({ id: '', name: '' })
}

function updateModelId(index: number, id: string) {
  const configuredModel = form.models[index]
  if (!configuredModel) return
  const previousId = configuredModel.id
  const previousCatalogName = providerModels.value.find((model) => model.id === previousId)?.name
  const previousSavedName = savedProvider.value?.models.find((model) => model.id === previousId)?.name
  configuredModel.id = id
  if (
    !configuredModel.name ||
    configuredModel.name === previousId ||
    configuredModel.name === previousCatalogName ||
    configuredModel.name === previousSavedName
  )
    configuredModel.name = id
  if (!form.model || form.model === previousId) form.model = id
  if (form.provider !== 'custom' && form.model === id) {
    const catalogModel = providerModels.value.find((model) => model.id === id)
    if (catalogModel) {
      form.api = catalogModel.api
      form.baseUrl = catalogModel.baseUrl
    }
  }
}

function updateActiveModel(model: string) {
  form.model = model
  if (form.provider === 'custom') return
  const catalogModel = providerModels.value.find((item) => item.id === model)
  if (catalogModel) {
    form.api = catalogModel.api
    form.baseUrl = catalogModel.baseUrl
  }
}

function removeModel(index: number) {
  const [removed] = form.models.splice(index, 1)
  if (removed?.id === form.model) form.model = form.models[0]?.id ?? ''
}

function defaultBaseUrl() {
  return (
    providerModels.value.find((model) => model.id === form.model)?.baseUrl ??
    providerModels.value[0]?.baseUrl ??
    ''
  )
}

function resetBaseUrl() {
  const value = defaultBaseUrl()
  if (value) form.baseUrl = value
}

async function fetchModels() {
  loadingModels.value = true
  try {
    if (form.provider !== 'custom') {
      providers.value = await aiAgentApi.modelCatalog()
      availableModels.value = providerModels.value.map((model) => model.id)
    } else {
      if (!savedProvider.value || form.baseUrl.trim() !== savedProvider.value.baseUrl) {
        getUiApi().message.warning('请先保存此自定义接口设置，再获取模型列表。')
        return
      }
      availableModels.value = await store.loadModels(form.provider)
    }
    getUiApi().message.success(`已获取 ${availableModels.value.length} 个模型。`)
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '获取模型列表失败。')
  } finally {
    loadingModels.value = false
  }
}

function validateForm() {
  if (!form.baseUrl.trim() || !form.model.trim()) {
    getUiApi().message.warning('请填写 Base URL 和模型。')
    return false
  }
  if (form.models.some((model) => !model.id.trim() || !model.name.trim())) {
    getUiApi().message.warning('请完整填写每个模型的 ID 和显示名称。')
    return false
  }
  const modelIds = form.models.map((model) => model.id.trim())
  if (new Set(modelIds).size !== modelIds.length) {
    getUiApi().message.warning('模型 ID 不能重复。')
    return false
  }
  return true
}

async function save() {
  if (saving.value || testing.value) return
  if (!validateForm()) return
  saving.value = true
  try {
    await store.saveProvider(form.provider, payload())
    form.apiKey = ''
    getUiApi().message.success(`供应商「${providerDisplayName(form.provider)}」配置已保存。`)
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '保存设置失败。')
  } finally {
    saving.value = false
  }
}

async function activate() {
  if (activating.value || !savedProvider.value) return
  activating.value = true
  try {
    await store.activateModel({
      provider: savedProvider.value.id,
      model: savedProvider.value.model,
    })
    getUiApi().message.success(`已切换到「${providerDisplayName(form.provider)}」。`)
    emit('update:show', false)
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '切换供应商失败。')
  } finally {
    activating.value = false
  }
}

async function removeProvider() {
  const saved = savedProvider.value
  if (!saved || isActiveProvider.value) return
  const dialog = getUiApi().dialog.warning({
    title: '删除供应商配置',
    content: `将删除「${providerDisplayName(saved.id)}」的模型列表和${
      saved.id === 'openai-codex' ? '登录凭据' : 'API Key'
    }，此操作不可恢复。确认继续？`,
    positiveText: '删除',
    negativeText: '取消',
    onPositiveClick: async () => {
      dialog.loading = true
      deleting.value = true
      try {
        await store.removeProvider(saved.id)
        selectProvider(store.settings?.provider ?? 'custom')
        getUiApi().message.success('供应商配置已删除。')
      } catch (error) {
        getUiApi().message.error(error instanceof Error ? error.message : '删除供应商配置失败。')
      } finally {
        dialog.loading = false
        deleting.value = false
      }
    },
  })
}

async function test() {
  if (!validateForm()) return
  testing.value = true
  try {
    await store.testSettings({ provider: form.provider, ...payload() })
    getUiApi().message.success('连接测试成功。')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '连接测试失败。')
  } finally {
    testing.value = false
  }
}

function clearKey() {
  const dialog = getUiApi().dialog.warning({
    title: '清除 API Key',
    content: '清除后，AI Agent 将无法调用需要鉴权的模型服务。确认继续？',
    positiveText: '清除',
    negativeText: '取消',
    onPositiveClick: async () => {
      dialog.loading = true
      try {
        await store.saveProvider(form.provider, { clearApiKey: true })
        form.apiKey = ''
        getUiApi().message.success('API Key 已清除。')
      } catch (error) {
        getUiApi().message.error(error instanceof Error ? error.message : '清除密钥失败。')
      } finally {
        dialog.loading = false
      }
    },
  })
}

async function toggleRemoteSkills(value: boolean) {
  try {
    await store.saveSettings({ showRemoteSkills: value })
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '保存设置失败。')
  }
}

function providerStatusLabel(provider: { id: string; hasCredentials: boolean }) {
  if (provider.hasCredentials) return provider.id === 'openai-codex' ? '已登录' : '已配置'
  return '缺少凭据'
}
</script>

<template>
  <NModal
    :show="show"
    preset="card"
    title="AI Agent 设置"
    class="agent-settings-modal"
    :bordered="false"
    @update:show="changeVisibility"
  >
    <NTabs :value="activeTab" type="line" animated @update:value="changeTab">
      <NTabPane name="model" tab="模型">
        <NAlert v-if="catalogError" type="error" class="mb-3">{{ catalogError }}</NAlert>
        <div class="provider-manager">
          <aside class="provider-sidebar">
            <div class="provider-list app-scrollbar app-scrollbar-compact">
              <button
                v-for="provider in configuredProviders"
                :key="provider.id"
                type="button"
                class="provider-item"
                :class="{ 'provider-item-active': provider.id === form.provider }"
                @click="chooseProvider(provider.id)"
              >
                <span class="provider-item-main">
                  <strong>{{ providerDisplayName(provider.id) }}</strong>
                  <span class="provider-item-meta">
                    <CheckCircle2
                      v-if="provider.hasCredentials"
                      :size="12"
                      class="provider-status-ok"
                    />
                    <TriangleAlert v-else :size="12" class="provider-status-warn" />
                    {{ providerStatusLabel(provider) }} · {{ provider.models.length }} 个模型
                  </span>
                </span>
                <span v-if="provider.id === store.settings?.provider" class="provider-item-current">
                  当前
                </span>
              </button>
              <button
                v-if="isDraftProvider"
                type="button"
                class="provider-item provider-item-active provider-item-draft"
              >
                <span class="provider-item-main">
                  <strong>{{ providerDisplayName(form.provider) }}</strong>
                  <span class="provider-item-meta">未保存的新配置</span>
                </span>
              </button>
            </div>
          </aside>
          <section class="provider-detail app-scrollbar">
            <div class="provider-detail-heading">
              <strong>{{ providerDisplayName(form.provider) }}</strong>
              <span v-if="isDraftProvider" class="provider-detail-badge">新配置，保存后生效</span>
              <span v-else-if="isActiveProvider" class="provider-detail-badge provider-detail-badge-current">当前使用</span>
              <NButton
                v-if="savedProvider && !isActiveProvider"
                class="provider-detail-delete"
                quaternary
                circle
                type="error"
                size="small"
                aria-label="删除配置"
                :loading="deleting"
                :disabled="saving || testing || activating"
                @click="removeProvider"
              >
                <Trash2 :size="15" />
              </NButton>
            </div>
            <NForm label-placement="top">
              <AiAgentOAuthLogin
                v-if="form.provider === 'openai-codex'"
                :active="show && activeTab === 'model'"
              />
              <NFormItem v-if="form.provider === 'custom'" label="API 协议">
                <NSelect v-model:value="form.api" :options="apiOptions" />
              </NFormItem>
              <NFormItem v-if="form.provider === 'custom'" label="Base URL">
                <div class="w-full">
                  <NInput v-model:value="form.baseUrl" placeholder="https://api.openai.com/v1" />
                  <div
                    v-if="usesPlainHttp"
                    class="mt-2 flex items-start gap-1 text-[11px] leading-4 text-amber-500"
                  >
                    <TriangleAlert :size="13" class="mt-[1px] shrink-0" />
                    <span>HTTP 不加密 API Key 和对话数据，仅用于可信网络。</span>
                  </div>
                </div>
              </NFormItem>
              <NFormItem v-if="form.provider !== 'openai-codex'" label="API Key">
                <div class="w-full">
                  <NInput
                    v-model:value="form.apiKey"
                    type="password"
                    show-password-on="click"
                    placeholder="留空以保留现有密钥"
                  />
                  <div class="mt-2 flex items-center justify-between gap-3 text-[11px]">
                    <span
                      v-if="savedProvider?.hasApiKey"
                      class="flex items-center gap-1 text-green-600"
                    >
                      <CheckCircle2 :size="13" /> 已配置密钥
                    </span>
                    <span v-else class="flex items-center gap-1 opacity-55">
                      <KeyRound :size="13" /> 未配置密钥
                    </span>
                    <NButton
                      v-if="savedProvider?.hasApiKey"
                      text
                      type="error"
                      size="tiny"
                      @click="clearKey"
                    >
                      清除密钥
                    </NButton>
                  </div>
                </div>
              </NFormItem>
              <div class="model-config-form-section">
                <div class="model-config-panel">
                  <div class="model-config-titlebar">
                    <span>模型配置</span>
                    <div class="model-config-actions">
                      <NButton
                        size="small"
                        :loading="loadingModels"
                        :disabled="saving || testing || (form.provider === 'custom' && !savedProvider?.hasApiKey)"
                        @click="fetchModels"
                      >
                        <RefreshCw :size="14" /> 获取模型列表
                      </NButton>
                      <NButton size="small" @click="addModel"> <Plus :size="14" /> 添加模型 </NButton>
                    </div>
                  </div>
                  <div class="model-config-headings">
                    <span>模型 ID</span>
                    <span>显示名称</span>
                  </div>
                  <div class="model-config-list app-scrollbar app-scrollbar-compact">
                    <div
                      v-for="(configuredModel, index) in form.models"
                      :key="index"
                      class="model-config-item"
                    >
                      <NSelect
                        :value="configuredModel.id || null"
                        :options="modelOptions"
                        filterable
                        tag
                        placeholder="选择或手动输入模型 ID"
                        @update:value="updateModelId(index, $event)"
                      />
                      <NInput v-model:value="configuredModel.name" placeholder="显示名称" />
                      <NButton
                        quaternary
                        circle
                        type="error"
                        :aria-label="`移除模型 ${configuredModel.name || configuredModel.id}`"
                        @click="removeModel(index)"
                      >
                        <Trash2 :size="15" />
                      </NButton>
                    </div>
                    <div v-if="form.models.length === 0" class="model-config-empty">尚未添加模型</div>
                  </div>
                </div>
              </div>
              <NFormItem label="默认模型">
                <NSelect
                  :value="form.model"
                  :options="selectedModelOptions"
                  placeholder="请先添加模型"
                  @update:value="updateActiveModel"
                />
              </NFormItem>
              <div v-if="form.provider !== 'custom' && form.provider !== 'openai-codex'" class="provider-advanced">
                <button type="button" class="provider-advanced-toggle" @click="advancedOpen = !advancedOpen">
                  <ChevronDown :size="13" :class="{ 'provider-advanced-open': advancedOpen }" />
                  高级设置
                </button>
                <div v-if="advancedOpen" class="provider-advanced-body">
                  <NFormItem label="API 协议">
                    <NSelect v-model:value="form.api" :options="apiOptions" />
                  </NFormItem>
                  <NFormItem label="Base URL">
                    <div class="w-full">
                      <div class="flex items-center gap-2">
                        <NInput v-model:value="form.baseUrl" placeholder="https://api.openai.com/v1" />
                        <NButton
                          quaternary
                          circle
                          size="small"
                          aria-label="恢复默认 Base URL"
                          @click="resetBaseUrl"
                        >
                          <RotateCcw :size="14" />
                        </NButton>
                      </div>
                      <div
                        v-if="usesPlainHttp"
                        class="mt-2 flex items-start gap-1 text-[11px] leading-4 text-amber-500"
                      >
                        <TriangleAlert :size="13" class="mt-[1px] shrink-0" />
                        <span>HTTP 不加密 API Key 和对话数据，仅用于可信网络。</span>
                      </div>
                    </div>
                  </NFormItem>
                </div>
              </div>
            </NForm>
          </section>
        </div>
        <div class="provider-footer">
          <NSelect
            class="provider-add"
            :value="null"
            :options="addableProviderOptions"
            filterable
            placeholder="添加供应商"
            @update:value="(value: string | null) => value && chooseProvider(value)"
          />
          <div class="provider-footer-actions">
            <NButton :loading="testing" :disabled="saving || activating" secondary @click="test">
              测试连接
            </NButton>
            <NButton
              v-if="!isActiveProvider"
              :loading="activating"
              :disabled="saving || testing || dirty || !savedProvider?.hasCredentials"
              secondary
              @click="activate"
            >
              设为当前
            </NButton>
            <NButton
              type="primary"
              :loading="saving"
              :disabled="testing || activating || !dirty"
              @click="save"
            >
              保存
            </NButton>
          </div>
        </div>
      </NTabPane>
      <NTabPane name="mcp" tab="MCP">
        <AiAgentMcpSettings />
      </NTabPane>
      <NTabPane name="tools" tab="工具">
        <AiAgentToolList :active="activeTab === 'tools'" />
      </NTabPane>
      <NTabPane name="skills" tab="Skills">
        <div class="skill-tab-toolbar">
          <span>远端主机 Skills</span>
          <NSwitch
            :value="store.settings?.showRemoteSkills ?? false"
            @update:value="toggleRemoteSkills"
          >
            <template #checked>显示</template>
            <template #unchecked>隐藏</template>
          </NSwitch>
        </div>
        <AiAgentSkillSettings ref="skillSettings" />
      </NTabPane>
    </NTabs>
  </NModal>
</template>

<style>
.agent-settings-modal {
  --provider-sidebar-width: 240px;
  width: min(980px, calc(100vw - 28px));
}

.provider-manager {
  display: grid;
  grid-template-columns: var(--provider-sidebar-width) minmax(0, 1fr);
  gap: 16px;
  align-items: stretch;
}

.provider-sidebar {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.provider-list {
  display: grid;
  flex: 1;
  min-height: 0;
  align-content: start;
  gap: 6px;
  overflow-y: auto;
}

.provider-item {
  display: flex;
  width: 100%;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 8px 10px;
  border: 1px solid var(--n-border-color);
  border-radius: 8px;
  background: transparent;
  cursor: pointer;
  text-align: left;
}

.provider-item:hover {
  border-color: var(--n-primary-color-hover);
}

.provider-item-active {
  border-color: var(--n-primary-color);
  background: color-mix(in srgb, var(--n-primary-color) 8%, transparent);
}

.provider-item-draft {
  border-style: dashed;
}

.provider-item-main {
  display: grid;
  min-width: 0;
  gap: 2px;
}

.provider-item-main strong {
  overflow: hidden;
  font-size: 13px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.provider-item-meta {
  display: flex;
  align-items: center;
  gap: 4px;
  color: var(--n-text-color-3);
  font-size: 11px;
}

.provider-status-ok {
  color: #18a058;
}

.provider-status-warn {
  color: #f0a020;
}

.provider-item-current {
  flex-shrink: 0;
  padding: 1px 6px;
  border-radius: 999px;
  background: var(--n-primary-color);
  color: #fff;
  font-size: 10px;
}

.provider-footer {
  display: grid;
  grid-template-columns: var(--provider-sidebar-width) minmax(0, 1fr);
  gap: 16px;
  align-items: center;
  margin-top: 16px;
}

.provider-add {
  width: 100%;
}

.provider-footer-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}

.skill-tab-toolbar {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 10px;
  margin-bottom: 10px;
  font-size: 12px;
}

.provider-detail {
  max-height: 520px;
  overflow-y: auto;
  padding-right: 4px;
}

.provider-detail-heading {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
  font-size: 15px;
}

.provider-detail-badge {
  padding: 1px 8px;
  border-radius: 999px;
  background: var(--n-border-color);
  font-size: 11px;
}

.provider-detail-badge-current {
  background: var(--n-primary-color);
  color: #fff;
}

.provider-detail-delete {
  margin-left: auto;
}

.provider-advanced {
  margin-bottom: 12px;
}

.provider-advanced-toggle {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 0;
  border: 0;
  background: transparent;
  color: var(--n-text-color-3);
  cursor: pointer;
  font-size: 12px;
}

.provider-advanced-toggle svg {
  transition: transform 0.15s ease;
}

.provider-advanced-toggle svg.provider-advanced-open {
  transform: rotate(180deg);
}

.provider-advanced-body {
  margin-top: 10px;
}

.model-config-panel {
  display: grid;
  width: 100%;
  gap: 8px;
}

.model-config-form-section {
  margin-top: -8px;
  margin-bottom: 18px;
}

.model-config-actions {
  display: flex;
  gap: 8px;
}

.model-config-titlebar {
  display: flex;
  min-height: 28px;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  font-size: 14px;
  font-weight: 500;
}

.model-config-headings,
.model-config-item {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1.12fr) 32px;
  align-items: center;
  gap: 8px;
}

.model-config-list {
  display: grid;
  max-height: 224px;
  gap: 8px;
  overflow-y: auto;
  padding-right: 3px;
}

.model-config-headings {
  padding: 0 4px;
  color: var(--n-text-color-3);
  font-size: 11px;
}

.model-config-empty {
  padding: 18px 0;
  color: var(--n-text-color-3);
  text-align: center;
  font-size: 12px;
}

@media (max-width: 720px) {
  .provider-manager {
    grid-template-columns: minmax(0, 1fr);
  }

  .provider-footer {
    grid-template-columns: minmax(0, 1fr);
  }

  .provider-list {
    display: flex;
    flex: none;
    overflow-x: auto;
    overflow-y: hidden;
  }

  .provider-item {
    width: 200px;
    flex-shrink: 0;
  }
}

@media (max-width: 420px) {
  .model-config-headings,
  .model-config-item {
    grid-template-columns: minmax(0, 1fr) 32px;
  }

  .model-config-headings span:nth-child(2),
  .model-config-item > :nth-child(2) {
    display: none;
  }
}
</style>

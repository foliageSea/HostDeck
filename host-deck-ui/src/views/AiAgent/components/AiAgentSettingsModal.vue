<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { CheckCircle2, KeyRound, Plus, RefreshCw, Trash2, TriangleAlert } from '@lucide/vue'
import type { AiAgentModelConfig, AiAgentSettingsUpdate } from '@/api/ai-agent'
import { getUiApi } from '@/lib/ui'
import { useAiAgentStore } from '@/stores/ai-agent'
import AiAgentMcpSettings from './AiAgentMcpSettings.vue'
import AiAgentSkillSettings from './AiAgentSkillSettings.vue'

const props = defineProps<{
  show: boolean
  initialTab?: 'mcp' | 'model' | 'skills'
}>()

const emit = defineEmits<{
  'update:show': [value: boolean]
}>()

const store = useAiAgentStore()
const skillSettings = ref<InstanceType<typeof AiAgentSkillSettings> | null>(null)
const saving = ref(false)
const testing = ref(false)
const loadingModels = ref(false)
const activeTab = ref<'mcp' | 'model' | 'skills'>('model')

function confirmLeavingSkills(action: () => void) {
  if (activeTab.value !== 'skills' || !skillSettings.value?.dirty) {
    action()
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
    activeTab.value = value as 'model' | 'mcp' | 'skills'
  })
}

function changeVisibility(value: boolean) {
  if (value) return emit('update:show', true)
  confirmLeavingSkills(() => emit('update:show', false))
}
const form = reactive({
  baseUrl: '',
  model: '',
  models: [] as AiAgentModelConfig[],
  apiKey: '',
  showRemoteSkills: false,
})
const availableModels = ref<string[]>([])
const usesPlainHttp = computed(() => /^http:\/\//i.test(form.baseUrl.trim()))
const modelOptions = computed(() =>
  availableModels.value.map((model) => ({
    label: model,
    value: model,
  })),
)
const selectedModelOptions = computed(() =>
  form.models
    .filter((model) => model.id.trim())
    .map((model) => ({ label: model.name.trim() || model.id, value: model.id })),
)

function syncForm() {
  form.baseUrl = store.settings?.baseUrl ?? ''
  form.model = store.settings?.model ?? ''
  form.models = (store.settings?.models ?? []).map((model) => ({ ...model }))
  form.showRemoteSkills = store.settings?.showRemoteSkills ?? false
  if (form.model && !form.models.some((item) => item.id === form.model)) {
    form.models.push({ id: form.model, name: form.model })
  }
  form.apiKey = ''
}

watch(
  () => props.show,
  async (show) => {
    if (!show) return
    activeTab.value = props.initialTab ?? 'model'
    try {
      if (!store.settings) await store.loadSettings()
      syncForm()
    } catch (error) {
      getUiApi().message.error(error instanceof Error ? error.message : '加载 AI 设置失败。')
    }
  },
  { immediate: true },
)

function payload() {
  const apiKey = form.apiKey.trim()
  return {
    baseUrl: form.baseUrl.trim(),
    model: form.model.trim(),
    models: form.models.map((model) => ({ id: model.id.trim(), name: model.name.trim() })),
    showRemoteSkills: form.showRemoteSkills,
    ...(apiKey ? { apiKey } : {}),
  }
}

function isSettingsUnchanged(payload: AiAgentSettingsUpdate) {
  const current = store.settings
  if (!current || payload.apiKey || payload.clearApiKey) return false

  const currentModels = current.models.map((model) => ({
    id: model.id.trim(),
    name: model.name.trim(),
  }))
  if (current.model && !currentModels.some((model) => model.id === current.model)) {
    currentModels.push({ id: current.model, name: current.model })
  }

  return (
    payload.baseUrl === current.baseUrl &&
    payload.model === current.model &&
    payload.models?.length === currentModels.length &&
    payload.showRemoteSkills === current.showRemoteSkills &&
    payload.models.every((model, index) => {
      const savedModel = currentModels[index]
      return model.id === savedModel?.id && model.name === savedModel?.name
    })
  )
}

function addModel() {
  form.models.push({ id: '', name: '' })
}

function updateModelId(index: number, id: string) {
  const configuredModel = form.models[index]
  if (!configuredModel) return
  const previousId = configuredModel.id
  configuredModel.id = id
  if (!configuredModel.name || configuredModel.name === previousId) configuredModel.name = id
  if (!form.model || form.model === previousId) form.model = id
}

function removeModel(index: number) {
  const [removed] = form.models.splice(index, 1)
  if (removed?.id === form.model) form.model = form.models[0]?.id ?? ''
}

async function fetchModels() {
  loadingModels.value = true
  try {
    availableModels.value = await store.loadModels()
    getUiApi().message.success(`已获取 ${availableModels.value.length} 个模型。`)
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '获取模型列表失败。')
  } finally {
    loadingModels.value = false
  }
}

async function save() {
  if (saving.value || testing.value) return
  if (!form.baseUrl.trim() || !form.model.trim()) {
    getUiApi().message.warning('请填写 Base URL 和模型。')
    return
  }
  if (form.models.some((model) => !model.id.trim() || !model.name.trim())) {
    getUiApi().message.warning('请完整填写每个模型的 ID 和显示名称。')
    return
  }
  const modelIds = form.models.map((model) => model.id.trim())
  if (new Set(modelIds).size !== modelIds.length) {
    getUiApi().message.warning('模型 ID 不能重复。')
    return
  }
  const nextPayload = payload()
  if (isSettingsUnchanged(nextPayload)) {
    form.apiKey = ''
    emit('update:show', false)
    return
  }

  saving.value = true
  try {
    await store.saveSettings(nextPayload)
    syncForm()
    getUiApi().message.success('AI Agent 设置已保存。')
    emit('update:show', false)
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '保存设置失败。')
  } finally {
    saving.value = false
  }
}

async function test() {
  if (!form.baseUrl.trim() || !form.model.trim()) {
    getUiApi().message.warning('请先填写 Base URL 和模型。')
    return
  }
  testing.value = true
  try {
    await store.testSettings(payload())
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
        await store.saveSettings({ clearApiKey: true })
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
        <NForm label-placement="top">
          <NFormItem label="Base URL">
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
          <div class="model-config-form-section">
            <div class="model-config-panel">
              <div class="model-config-titlebar">
                <span>模型配置</span>
                <div class="model-config-actions">
                  <NButton
                    size="small"
                    :loading="loadingModels"
                    :disabled="saving || testing || !store.settings?.hasApiKey"
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
          <NFormItem label="当前模型">
            <NSelect
              v-model:value="form.model"
              :options="selectedModelOptions"
              placeholder="请先添加模型"
            />
          </NFormItem>
          <NFormItem label="API Key">
            <div class="w-full">
              <NInput
                v-model:value="form.apiKey"
                type="password"
                show-password-on="click"
                placeholder="留空以保留现有密钥"
              />
              <div class="mt-2 flex items-center justify-between gap-3 text-[11px]">
                <span
                  v-if="store.settings?.hasApiKey"
                  class="flex items-center gap-1 text-green-600"
                >
                  <CheckCircle2 :size="13" /> 已配置密钥
                </span>
                <span v-else class="flex items-center gap-1 opacity-55">
                  <KeyRound :size="13" /> 未配置密钥
                </span>
                <NButton
                  v-if="store.settings?.hasApiKey"
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
          <NFormItem label="远端主机 Skills">
            <NSwitch v-model:value="form.showRemoteSkills">
              <template #checked>显示</template>
              <template #unchecked>隐藏</template>
            </NSwitch>
          </NFormItem>
        </NForm>
      </NTabPane>
      <NTabPane name="mcp" tab="MCP">
        <AiAgentMcpSettings />
      </NTabPane>
      <NTabPane name="skills" tab="Skills">
        <AiAgentSkillSettings ref="skillSettings" />
      </NTabPane>
    </NTabs>
    <template #footer>
      <div v-if="activeTab === 'model'" class="flex justify-end gap-2">
        <NButton :loading="testing" :disabled="saving" secondary @click="test">测试连接</NButton>
        <NButton type="primary" :loading="saving" :disabled="testing" @click="save">保存</NButton>
      </div>
    </template>
  </NModal>
</template>

<style>
.agent-settings-modal {
  width: min(900px, calc(100vw - 28px));
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

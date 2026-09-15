<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { CheckCircle2, KeyRound, TriangleAlert } from '@lucide/vue'
import { getUiApi } from '@/lib/ui'
import { useAiAgentStore } from '@/stores/ai-agent'

const props = defineProps<{
  show: boolean
}>()

const emit = defineEmits<{
  'update:show': [value: boolean]
}>()

const store = useAiAgentStore()
const saving = ref(false)
const testing = ref(false)
const form = reactive({ baseUrl: '', model: '', apiKey: '' })
const usesPlainHttp = computed(() => /^http:\/\//i.test(form.baseUrl.trim()))

function syncForm() {
  form.baseUrl = store.settings?.baseUrl ?? ''
  form.model = store.settings?.model ?? ''
  form.apiKey = ''
}

watch(
  () => props.show,
  async (show) => {
    if (!show) return
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
    ...(apiKey ? { apiKey } : {}),
  }
}

async function save() {
  if (!form.baseUrl.trim() || !form.model.trim()) {
    getUiApi().message.warning('请填写 Base URL 和模型。')
    return
  }
  saving.value = true
  try {
    await store.saveSettings(payload())
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
    @update:show="emit('update:show', $event)"
  >
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
      <NFormItem label="模型">
        <NInput v-model:value="form.model" placeholder="例如 gpt-5" />
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
            <span v-if="store.settings?.hasApiKey" class="flex items-center gap-1 text-green-600">
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
    </NForm>
    <template #footer>
      <div class="flex justify-end gap-2">
        <NButton :loading="testing" :disabled="saving" secondary @click="test">测试连接</NButton>
        <NButton type="primary" :loading="saving" :disabled="testing" @click="save">保存</NButton>
      </div>
    </template>
  </NModal>
</template>

<style>
.agent-settings-modal {
  width: min(520px, calc(100vw - 28px));
}
</style>

<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { Copy } from '@lucide/vue'
import { aiAgentApi, type AiAgentOAuthStatus } from '@/api/ai-agent'
import { getUiApi } from '@/lib/ui'
import { useAiAgentStore } from '@/stores/ai-agent'

const props = defineProps<{ active: boolean }>()
const store = useAiAgentStore()
const status = ref<AiAgentOAuthStatus>()
const busy = ref(false)
const error = ref('')
const pending = computed(() => ['starting', 'pending'].includes(status.value?.status ?? ''))
let timer: ReturnType<typeof setTimeout> | undefined
let generation = 0

function stopPolling() {
  generation++
  clearTimeout(timer)
}

async function poll(version: number) {
  try {
    const value = await aiAgentApi.oauthStatus()
    if (version !== generation || !props.active) return
    status.value = value
    error.value = ''
    if (value.status === 'success') await store.loadSettings()
    if (version === generation && pending.value) timer = setTimeout(() => void poll(version), 2000)
  } catch (cause) {
    if (version !== generation) return
    error.value = cause instanceof Error ? cause.message : '读取登录状态失败。'
    timer = setTimeout(() => void poll(version), 4000)
  }
}

watch(() => props.active, (active) => {
  stopPolling()
  if (active) void poll(generation)
}, { immediate: true })
onBeforeUnmount(stopPolling)

async function login() {
  if (busy.value) return
  busy.value = true
  stopPolling()
  try {
    status.value = await aiAgentApi.oauthLogin()
    error.value = ''
    if (props.active) void poll(generation)
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : '启动登录失败。'
  } finally {
    busy.value = false
  }
}

async function cancel() {
  if (!status.value?.id || busy.value) return
  busy.value = true
  stopPolling()
  try {
    status.value = await aiAgentApi.oauthCancel(status.value.id)
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : '取消登录失败。'
  } finally {
    busy.value = false
  }
}

async function logout() {
  if (busy.value) return
  busy.value = true
  stopPolling()
  try {
    store.settings = await aiAgentApi.oauthLogout()
    status.value = { authenticated: false, status: 'idle' }
    error.value = ''
    getUiApi().message.success('已退出 OpenAI Codex。')
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : '退出登录失败。'
  } finally {
    busy.value = false
  }
}

async function copyUserCode() {
  const userCode = status.value?.userCode
  if (!userCode) return
  try {
    await navigator.clipboard.writeText(userCode.replaceAll('-', ''))
    getUiApi().message.success('设备码已复制。')
  } catch {
    getUiApi().message.error('复制设备码失败，请手动复制。')
  }
}
</script>

<template>
  <div class="agent-oauth-panel mb-4 p-3" :class="{ 'agent-oauth-panel-authenticated': status?.authenticated }">
    <div class="mb-2 text-sm font-medium">OpenAI / ChatGPT 账号登录</div>
    <p class="mb-3 text-xs opacity-60">使用支持 Codex 的 ChatGPT 订阅，通过设备码授权，无需 API Key。</p>
    <div v-if="status?.authenticated" class="mb-3 text-xs text-green-500">已登录，凭据将自动刷新。</div>
    <div v-if="pending" class="mb-3 text-xs" aria-live="polite">
      <template v-if="status?.userCode && status.verificationUri">
        <div>打开授权页面并输入设备码：</div>
        <div class="my-2 flex items-center gap-2">
          <code class="block select-text text-lg font-bold tracking-widest">{{ status.userCode }}</code>
          <NButton quaternary circle size="small" aria-label="复制设备码" @click="copyUserCode">
            <Copy :size="15" />
          </NButton>
        </div>
        <p class="mt-2 opacity-60">完成授权后自动更新。若页面要求，请在 ChatGPT 安全设置中启用设备码登录。</p>
      </template>
      <span v-else>正在获取设备码…</span>
    </div>
    <div v-if="error || status?.error" role="alert" class="mb-3 text-xs text-red-500">{{ error || status?.error }}</div>
    <div class="agent-oauth-actions flex gap-2">
      <NButton v-if="!pending" size="small" :loading="busy" @click="login">{{ status?.authenticated ? '重新登录' : '登录 OpenAI' }}</NButton>
      <NButton
        v-if="pending && status?.verificationUri"
        tag="a"
        size="small"
        :href="status.verificationUri"
        target="_blank"
        rel="noopener noreferrer"
      >
        打开 OpenAI 授权页面
      </NButton>
      <NButton v-if="pending" size="small" :loading="busy" @click="cancel">取消登录</NButton>
      <NButton v-if="status?.authenticated" size="small" :disabled="busy" @click="logout">退出登录</NButton>
    </div>
    <p class="mt-2 text-xs opacity-60">登录后保存模型设置，即可开始对话。</p>
  </div>
</template>

<style scoped>
.agent-oauth-panel {
  border: 1px solid var(--n-border-color);
  border-radius: var(--app-radius-item);
  background: color-mix(in srgb, var(--n-color-embedded) 72%, transparent);
  box-shadow: inset 0 1px 0 color-mix(in srgb, currentColor 3%, transparent);
  transition:
    border-color 160ms ease,
    background-color 160ms ease;
}

.agent-oauth-panel-authenticated {
  border-color: color-mix(in srgb, #22c55e 28%, var(--n-border-color));
  background: color-mix(in srgb, #22c55e 4%, var(--n-color-embedded));
}
</style>

<script setup lang="ts">
import { computed, nextTick, onMounted, reactive, ref } from 'vue'
import type { FormInst, FormItemRule, FormRules } from 'naive-ui'
import {
  portForwardApi,
  type PortForwardPayload,
  type PortForwardRule,
  type PortForwardStatus,
} from '@/api/port-forward'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const formRef = ref<FormInst | null>(null)
const rules = ref<PortForwardRule[]>([])
const loading = ref(false)
const saving = ref(false)
const operatingId = ref<number | null>(null)
const dialogVisible = ref(false)
const editingId = ref<number | null>(null)

const form = reactive({
  bindHost: '127.0.0.1',
  enabled: true,
  localPort: 8081,
  name: '',
  remoteHost: '127.0.0.1',
  remotePort: 80,
})

function validateRequiredText(fieldName: string) {
  return (_rule: FormItemRule, value: string) => {
    if (typeof value !== 'string' || value.trim().length === 0) {
      return new Error(`请输入${fieldName}`)
    }

    return true
  }
}

function isValidIpv4(value: string) {
  const segments = value.split('.')
  if (segments.length !== 4) {
    return false
  }

  return segments.every((segment) => {
    if (!/^\d+$/.test(segment)) {
      return false
    }

    const numericValue = Number(segment)
    return numericValue >= 0 && numericValue <= 255
  })
}

function validateHost(fieldName: string) {
  return (_rule: FormItemRule, value: string) => {
    const trimmedValue = value.trim()
    if (!trimmedValue) {
      return new Error(`请输入${fieldName}`)
    }

    if (trimmedValue !== 'localhost' && !isValidIpv4(trimmedValue)) {
      return new Error(`${fieldName}仅支持 IPv4 或 localhost`)
    }

    return true
  }
}

function validatePort(_rule: FormItemRule, value: number | null) {
  if (!Number.isInteger(value) || value === null || value < 1 || value > 65535) {
    return new Error('端口范围为 1-65535 的整数')
  }

  return true
}

function validateLocalEndpoint(_rule: FormItemRule, value: number | null) {
  const portResult = validatePort(_rule, value)
  if (portResult instanceof Error) {
    return portResult
  }

  const bindHost = form.bindHost.trim()
  if (!bindHost) {
    return true
  }

  const duplicateRule = rules.value.find((rule) => {
    if (editingId.value !== null && rule.id === editingId.value) {
      return false
    }

    return rule.bindHost.trim() === bindHost && rule.localPort === value
  })

  if (duplicateRule) {
    return new Error('该本地监听地址和端口已存在')
  }

  return true
}

const formRules: FormRules = {
  bindHost: [
    { required: true, validator: validateHost('本地绑定地址'), trigger: ['input', 'blur'] },
  ],
  localPort: [
    { required: true, validator: validateLocalEndpoint, trigger: ['input', 'blur', 'change'] },
  ],
  name: [{ required: true, validator: validateRequiredText('名称'), trigger: ['input', 'blur'] }],
  remoteHost: [{ required: true, validator: validateHost('远端主机'), trigger: ['input', 'blur'] }],
  remotePort: [{ required: true, validator: validatePort, trigger: ['input', 'blur', 'change'] }],
}

const hasConnection = computed(() => Boolean(sshStore.connectionId && sshStore.isConnected))
const connectionText = computed(() => {
  if (!hasConnection.value) {
    return '未连接 SSH'
  }

  return `${sshStore.username}@${sshStore.host}:${sshStore.port}`
})
const runningCount = computed(() => rules.value.filter((rule) => rule.status === 'running').length)
const enabledCount = computed(() => rules.value.filter((rule) => rule.enabled).length)

function statusType(status: PortForwardStatus) {
  if (status === 'running') {
    return 'success'
  }

  if (status === 'error') {
    return 'error'
  }

  return 'default'
}

function statusText(status: PortForwardStatus) {
  if (status === 'running') {
    return '运行中'
  }

  if (status === 'error') {
    return '异常'
  }

  return '已停止'
}

function localUrl(rule: PortForwardRule) {
  const host =
    rule.bindHost === '0.0.0.0' || rule.bindHost === '::' ? window.location.hostname : rule.bindHost
  return `http://${host}:${rule.localPort}`
}

function resetForm() {
  editingId.value = null
  form.bindHost = '127.0.0.1'
  form.enabled = true
  form.localPort = 8081
  form.name = ''
  form.remoteHost = '127.0.0.1'
  form.remotePort = 80
}

function payloadFromForm(): PortForwardPayload {
  return {
    bindHost: form.bindHost.trim(),
    enabled: form.enabled,
    localPort: Number(form.localPort),
    name: form.name.trim(),
    remoteHost: form.remoteHost.trim(),
    remotePort: Number(form.remotePort),
    connectionId: sshStore.connectionId,
  }
}

function upsertRule(nextRule: PortForwardRule) {
  const index = rules.value.findIndex((rule) => rule.id === nextRule.id)
  if (index === -1) {
    rules.value.unshift(nextRule)
    return
  }

  rules.value[index] = nextRule
}

async function fetchRules() {
  loading.value = true
  try {
    rules.value = await portForwardApi.list()
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '加载端口转发配置失败。')
  } finally {
    loading.value = false
  }
}

function openCreateDialog() {
  resetForm()
  dialogVisible.value = true
  void nextTick(() => formRef.value?.restoreValidation())
}

function openEditDialog(rule: PortForwardRule) {
  editingId.value = rule.id
  form.bindHost = rule.bindHost
  form.enabled = rule.enabled
  form.localPort = rule.localPort
  form.name = rule.name
  form.remoteHost = rule.remoteHost
  form.remotePort = rule.remotePort
  dialogVisible.value = true
  void nextTick(() => formRef.value?.restoreValidation())
}

async function submitForm() {
  await formRef.value?.validate()
  if (form.enabled && !hasConnection.value) {
    getUiApi().message.warning('启用端口转发前请先连接 SSH。')
    return
  }

  saving.value = true
  try {
    const payload = payloadFromForm()
    const nextRule =
      editingId.value === null
        ? await portForwardApi.create(payload)
        : await portForwardApi.update(editingId.value, payload)
    upsertRule(nextRule)
    dialogVisible.value = false
    getUiApi().message.success('端口转发配置已保存。')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '保存端口转发配置失败。')
  } finally {
    saving.value = false
  }
}

async function toggleRule(rule: PortForwardRule, value: boolean) {
  if (value && !hasConnection.value) {
    getUiApi().message.warning('启用端口转发前请先连接 SSH。')
    return
  }

  operatingId.value = rule.id
  try {
    const nextRule = value
      ? await portForwardApi.start(rule.id, sshStore.connectionId as string)
      : await portForwardApi.stop(rule.id)
    upsertRule(nextRule)
    getUiApi().message.success(value ? '端口转发已启动。' : '端口转发已停止。')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '更新端口转发状态失败。')
  } finally {
    operatingId.value = null
  }
}

function removeRule(rule: PortForwardRule) {
  getUiApi().dialog.warning({
    content: `删除后会停止“${rule.name}”并移除配置。`,
    negativeText: '取消',
    positiveText: '删除',
    title: '删除端口转发',
    onPositiveClick: async () => {
      operatingId.value = rule.id
      try {
        await portForwardApi.delete(rule.id)
        rules.value = rules.value.filter((item) => item.id !== rule.id)
        getUiApi().message.success('端口转发配置已删除。')
      } catch (error) {
        getUiApi().message.error(error instanceof Error ? error.message : '删除端口转发配置失败。')
      } finally {
        operatingId.value = null
      }
    },
  })
}

async function copyLocalUrl(rule: PortForwardRule) {
  await navigator.clipboard.writeText(localUrl(rule))
  getUiApi().message.success('本地访问地址已复制。')
}

onMounted(() => {
  void fetchRules()
})
</script>

<template>
  <div
    class="port-forward-view flex h-full flex-col gap-[16px] overflow-auto p-[20px]"
    :class="
      settingsStore.isDark
        ? 'bg-[radial-gradient(circle_at_top_left,rgba(56,189,248,0.12),transparent_32%),rgba(15,23,42,0.04)]'
        : 'bg-[radial-gradient(circle_at_top_left,rgba(14,165,233,0.16),transparent_32%),rgba(248,250,252,0.58)]'
    "
  >
    <div class="flex flex-wrap items-start justify-between gap-[12px]">
      <div>
        <div class="text-[24px] font-700 leading-tight">端口转发</div>
      </div>
      <NSpace>
        <NButton secondary :loading="loading" @click="fetchRules">刷新</NButton>
        <NButton type="primary" @click="openCreateDialog">新增转发</NButton>
      </NSpace>
    </div>

    <div class="grid grid-cols-3 gap-[12px] lt-md:grid-cols-1">
      <NCard size="small">
        <div class="text-[12px] text-[rgba(100,116,139,0.86)]">当前连接</div>
        <div class="mt-[8px] flex items-center gap-[8px] text-[15px] font-600">
          <NTag :type="hasConnection ? 'success' : 'warning'" size="small">{{
            hasConnection ? '已连接' : '未连接'
          }}</NTag>
          <span>{{ connectionText }}</span>
        </div>
      </NCard>
      <NCard size="small">
        <div class="text-[12px] text-[rgba(100,116,139,0.86)]">启用配置</div>
        <div class="mt-[8px] text-[26px] font-700">{{ enabledCount }}</div>
      </NCard>
      <NCard size="small">
        <div class="text-[12px] text-[rgba(100,116,139,0.86)]">运行中</div>
        <div class="mt-[8px] text-[26px] font-700 text-[#0ea5e9]">{{ runningCount }}</div>
      </NCard>
    </div>

    <NCard class="min-h-0 flex-1" content-style="height: 100%; padding: 0;" :bordered="false">
      <div v-if="loading" class="flex h-full min-h-[280px] items-center justify-center">
        <NSpin size="large" />
      </div>
      <NEmpty v-else-if="rules.length === 0" class="py-[76px]" description="暂无端口转发配置">
        <template #extra>
          <NButton type="primary" @click="openCreateDialog">新增第一条转发</NButton>
        </template>
      </NEmpty>
      <div v-else class="divide-y divide-[rgba(148,163,184,0.16)]">
        <div
          v-for="rule in rules"
          :key="rule.id"
          class="grid grid-cols-[1.25fr_1.4fr_1fr_auto] items-center gap-[16px] p-[16px] lt-lg:grid-cols-1"
        >
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-[8px]">
              <div class="truncate text-[15px] font-700">{{ rule.name }}</div>
              <NTag :type="statusType(rule.status)" size="small">{{
                statusText(rule.status)
              }}</NTag>
            </div>
            <div v-if="rule.error" class="mt-[6px] line-clamp-2 text-[12px] text-[#ef4444]">
              {{ rule.error }}
            </div>
            <div v-else class="mt-[6px] text-[12px] text-[rgba(100,116,139,0.82)]">
              活跃连接：{{ rule.activeConnections ?? 0 }}
            </div>
          </div>

          <div
            class="min-w-0 rounded-[12px] bg-[rgba(14,165,233,0.08)] px-[12px] py-[10px] text-[13px]"
          >
            <div class="truncate font-600">本地：{{ rule.bindHost }}:{{ rule.localPort }}</div>
            <div class="mt-[4px] truncate text-[rgba(100,116,139,0.88)]">
              远端：{{ rule.remoteHost }}:{{ rule.remotePort }}
            </div>
          </div>

          <div class="min-w-0">
            <div class="truncate text-[13px] font-600">{{ localUrl(rule) }}</div>
            <NButton text type="primary" size="small" @click="copyLocalUrl(rule)"
              >复制访问地址</NButton
            >
          </div>

          <NSpace justify="end" align="center">
            <NSwitch
              :value="rule.enabled"
              :loading="operatingId === rule.id"
              @update:value="toggleRule(rule, $event)"
            />
            <NButton size="small" secondary @click="openEditDialog(rule)">编辑</NButton>
            <NButton
              size="small"
              secondary
              type="error"
              :loading="operatingId === rule.id"
              @click="removeRule(rule)"
              >删除</NButton
            >
          </NSpace>
        </div>
      </div>
    </NCard>

    <NModal
      v-model:show="dialogVisible"
      preset="card"
      :title="editingId === null ? '新增端口转发' : '编辑端口转发'"
      class="max-w-[560px]"
    >
      <NForm ref="formRef" :model="form" :rules="formRules" label-placement="top">
        <NFormItem label="名称" path="name">
          <NInput v-model:value="form.name" placeholder="例如：远端 Web 服务" />
        </NFormItem>
        <div class="grid grid-cols-2 gap-[12px] lt-md:grid-cols-1">
          <NFormItem label="本地绑定地址" path="bindHost">
            <NInput v-model:value="form.bindHost" placeholder="127.0.0.1" />
          </NFormItem>
          <NFormItem label="本地端口" path="localPort">
            <NInputNumber v-model:value="form.localPort" class="w-full" :min="1" :max="65535" />
          </NFormItem>
        </div>
        <div class="grid grid-cols-2 gap-[12px] lt-md:grid-cols-1">
          <NFormItem label="远端主机" path="remoteHost">
            <NInput v-model:value="form.remoteHost" placeholder="127.0.0.1" />
          </NFormItem>
          <NFormItem label="远端端口" path="remotePort">
            <NInputNumber v-model:value="form.remotePort" class="w-full" :min="1" :max="65535" />
          </NFormItem>
        </div>
        <NFormItem label="保存后启用">
          <NSwitch v-model:value="form.enabled" />
        </NFormItem>
      </NForm>
      <template #footer>
        <div class="flex justify-end gap-[10px]">
          <NButton @click="dialogVisible = false">取消</NButton>
          <NButton type="primary" :loading="saving" @click="submitForm">保存</NButton>
        </div>
      </template>
    </NModal>
  </div>
</template>

<style scoped>
.port-forward-view::-webkit-scrollbar {
  width: 0;
  height: 0;
  display: none;
}
</style>

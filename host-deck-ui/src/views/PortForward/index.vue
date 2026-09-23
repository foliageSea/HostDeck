<script setup lang="ts">
import { computed, nextTick, onMounted, reactive, ref } from 'vue'
import {
  Copy,
  Laptop,
  Maximize2,
  Network,
  Pencil,
  Plus,
  RefreshCw,
  Server,
  Trash2,
} from '@lucide/vue'
import { Background } from '@vue-flow/background'
import { Controls } from '@vue-flow/controls'
import { Handle, Position, VueFlow, useVueFlow } from '@vue-flow/core'
import type { Edge, Node } from '@vue-flow/core'
import '@vue-flow/core/dist/style.css'
import '@vue-flow/core/dist/theme-default.css'
import '@vue-flow/controls/dist/style.css'
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
const { fitView } = useVueFlow({ id: 'port-forward-flow' })
const formRef = ref<FormInst | null>(null)
const rules = ref<PortForwardRule[]>([])
const loading = ref(false)
const saving = ref(false)
const operatingId = ref<number | null>(null)
const dialogVisible = ref(false)
const editingId = ref<number | null>(null)
const hasFittedDiagram = ref(false)

interface PortForwardNodeData {
  rule: PortForwardRule | null
}

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
const totalCount = computed(() => rules.value.length)
const flowNodes = computed<Node<PortForwardNodeData>[]>(() => {
  if (rules.value.length === 0) {
    return []
  }

  const hostNode: Node<PortForwardNodeData> = {
    id: 'ssh-host',
    type: 'host',
    position: { x: 36, y: 54 + (rules.value.length - 1) * 95 },
    draggable: false,
    selectable: false,
    connectable: false,
    data: { rule: null },
  }
  const serviceNodes = rules.value.flatMap((rule, index) => {
    const rowTop = index * 190 + 36
    const nodeDefaults = {
      draggable: false,
      selectable: true,
      connectable: false,
      data: { rule },
    }

    return [
      {
        ...nodeDefaults,
        id: `remote:${rule.id}`,
        type: 'remote',
        position: { x: 350, y: rowTop },
      },
      {
        ...nodeDefaults,
        id: `local:${rule.id}`,
        type: 'local',
        position: { x: 734, y: rowTop + 18 },
      },
    ]
  })

  return [hostNode, ...serviceNodes]
})
const flowEdges = computed<Edge[]>(() =>
  rules.value.flatMap((rule) => {
    const color =
      rule.status === 'running' ? '#16a34a' : rule.status === 'error' ? '#ef4444' : '#94a3b8'
    const edgeDefaults = {
      animated: rule.enabled,
      type: 'smoothstep',
      style: { stroke: color, strokeWidth: rule.status === 'running' ? 2.4 : 1.7 },
    }

    return [
      {
        ...edgeDefaults,
        id: `host-remote:${rule.id}`,
        source: 'ssh-host',
        target: `remote:${rule.id}`,
      },
      {
        ...edgeDefaults,
        id: `remote-local:${rule.id}`,
        source: `remote:${rule.id}`,
        target: `local:${rule.id}`,
      },
    ]
  }),
)

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

function localAddress(rule: PortForwardRule) {
  const host =
    rule.bindHost === '0.0.0.0' || rule.bindHost === '::' ? window.location.hostname : rule.bindHost
  return `${host}:${rule.localPort}`
}

function fitDiagram() {
  void nextTick(() => fitView({ padding: 0.12, maxZoom: 1, duration: 280 }))
}

function handleNodesInitialized() {
  if (hasFittedDiagram.value || flowNodes.value.length === 0) {
    return
  }

  hasFittedDiagram.value = true
  fitDiagram()
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
  await navigator.clipboard.writeText(localAddress(rule))
  getUiApi().message.success('本地监听地址已复制。')
}

onMounted(() => {
  void fetchRules()
})
</script>

<template>
  <div
    class="port-forward-view flex h-full min-h-0 flex-col"
    :class="{ 'is-dark': settingsStore.isDark }"
  >
    <header class="flow-header">
      <div class="min-w-0">
        <div class="flex items-center gap-[10px]">
          <div class="flow-title-icon"><Network :size="18" /></div>
          <div>
            <h1 class="m-0 text-[20px] font-700 leading-tight">端口转发</h1>
            <div class="mt-[4px] text-[12px] opacity-60">将 SSH 主机上的远程服务转发到本地端口</div>
          </div>
        </div>
      </div>
      <div class="flex flex-wrap items-center justify-end gap-[8px]">
        <div class="connection-pill" :class="{ connected: hasConnection }">
          <i aria-hidden="true"></i>
          <span class="max-w-[260px] truncate">{{ connectionText }}</span>
        </div>
        <div class="flow-metric">
          <strong>{{ runningCount }}</strong
          ><span>运行</span>
        </div>
        <div class="flow-metric">
          <strong>{{ totalCount }}</strong
          ><span>规则</span>
        </div>
        <NTooltip>
          <template #trigger>
            <NButton circle secondary aria-label="适配画布" @click="fitDiagram">
              <template #icon><Maximize2 :size="16" /></template>
            </NButton>
          </template>
          适配全部流程
        </NTooltip>
        <NTooltip>
          <template #trigger>
            <NButton circle secondary :loading="loading" aria-label="刷新" @click="fetchRules">
              <template #icon><RefreshCw :size="16" /></template>
            </NButton>
          </template>
          刷新规则
        </NTooltip>
        <NButton type="primary" @click="openCreateDialog">
          <template #icon><Plus :size="16" /></template>
          新增转发
        </NButton>
      </div>
    </header>

    <main class="flow-canvas">
      <VueFlow
        id="port-forward-flow"
        :nodes="flowNodes"
        :edges="flowEdges"
        :nodes-draggable="false"
        :min-zoom="0.35"
        :max-zoom="1.5"
        :zoom-on-double-click="false"
        :delete-key-code="null"
        @nodes-initialized="handleNodesInitialized"
      >
        <Background :gap="22" :size="1.2" :color="settingsStore.isDark ? '#334155' : '#cbd5e1'" />
        <Controls position="bottom-left" />

        <template #node-host>
          <article class="endpoint-node host-node">
            <div class="node-icon"><Server :size="20" /></div>
            <div class="min-w-0 flex-1">
              <div class="node-label">SSH 主机</div>
              <div class="node-address" :title="connectionText">{{ connectionText }}</div>
              <div class="node-caption">{{ totalCount }} 个远程服务</div>
            </div>
            <Handle type="source" :position="Position.Right" />
          </article>
        </template>

        <template #node-remote="{ data }">
          <article
            v-if="data.rule"
            class="service-node"
            :class="`status-${data.rule.status}`"
            :aria-label="`${data.rule.name}，${statusText(data.rule.status)}`"
          >
            <Handle type="target" :position="Position.Left" />
            <div class="service-heading">
              <div class="min-w-0">
                <div class="node-label">远程服务</div>
                <div class="truncate text-[15px] font-700" :title="data.rule.name">
                  {{ data.rule.name }}
                </div>
              </div>
              <NTag :type="statusType(data.rule.status)" size="small">
                {{ statusText(data.rule.status) }}
              </NTag>
            </div>
            <div v-if="data.rule.error" class="node-error" :title="data.rule.error">
              {{ data.rule.error }}
            </div>
            <div v-else class="service-meta">
              <span>{{ data.rule.remoteHost }}:{{ data.rule.remotePort }}</span>
              <span>活跃连接 {{ data.rule.activeConnections ?? 0 }}</span>
            </div>
            <div
              class="service-actions nodrag nopan nowheel"
              @pointerdown.stop
              @mousedown.stop
              @click.stop
            >
              <div class="flex items-center gap-[7px]" @click.stop>
                <NSwitch
                  :value="data.rule.enabled"
                  :loading="operatingId === data.rule.id"
                  size="small"
                  @click.stop
                  @update:value="toggleRule(data.rule, $event)"
                />
                <span>{{ data.rule.enabled ? '已启用' : '已停用' }}</span>
              </div>
              <div class="flex items-center gap-[2px]">
                <NTooltip>
                  <template #trigger>
                    <button
                      class="icon-action"
                      type="button"
                      aria-label="编辑"
                      @mousedown.stop
                      @click="openEditDialog(data.rule)"
                    >
                      <Pencil :size="14" />
                    </button>
                  </template>
                  编辑规则
                </NTooltip>
                <NTooltip>
                  <template #trigger>
                    <button
                      class="icon-action danger"
                      type="button"
                      aria-label="删除"
                      @mousedown.stop
                      @click="removeRule(data.rule)"
                    >
                      <Trash2 :size="14" />
                    </button>
                  </template>
                  删除规则
                </NTooltip>
              </div>
            </div>
            <Handle type="source" :position="Position.Right" />
          </article>
        </template>

        <template #node-local="{ data }">
          <article v-if="data.rule" class="endpoint-node local-node">
            <Handle type="target" :position="Position.Left" />
            <div class="node-icon"><Laptop :size="20" /></div>
            <div class="min-w-0 flex-1">
              <div class="node-label">本地服务</div>
              <div class="node-address" :title="localAddress(data.rule)">
                {{ localAddress(data.rule) }}
              </div>
              <button
                class="node-link nodrag nopan"
                type="button"
                @pointerdown.stop
                @click.stop="copyLocalUrl(data.rule)"
              >
                <Copy :size="12" />复制地址
              </button>
            </div>
          </article>
        </template>
      </VueFlow>

      <div v-if="loading" class="canvas-overlay"><NSpin size="large" /></div>
      <div v-else-if="rules.length === 0" class="canvas-overlay">
        <NEmpty description="暂无端口转发流程">
          <template #extra>
            <NButton type="primary" @click="openCreateDialog">
              <template #icon><Plus :size="16" /></template>
              创建第一条流程
            </NButton>
          </template>
        </NEmpty>
      </div>

      <div class="flow-legend">
        <span><i class="running"></i>运行中</span>
        <span><i class="stopped"></i>已停止</span>
        <span><i class="error"></i>异常</span>
      </div>
    </main>

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
        <NFormItem label="保存并启动">
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
.port-forward-view {
  color: #172033;
  background: #f4f7fa;
}

.port-forward-view.is-dark {
  color: #e5e7eb;
  background: #111827;
}

.flow-header {
  z-index: 2;
  display: flex;
  min-height: 78px;
  flex: 0 0 auto;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
  padding: 13px 20px;
  border-bottom: 1px solid #dbe2ea;
  background: rgba(255, 255, 255, 0.9);
}

.is-dark .flow-header {
  border-bottom-color: #273244;
  background: rgba(17, 24, 39, 0.94);
}

.flow-title-icon {
  display: grid;
  width: 34px;
  height: 34px;
  flex: 0 0 auto;
  place-items: center;
  border-radius: 10px;
  color: #0369a1;
  background: #e0f2fe;
}

.is-dark .flow-title-icon {
  color: #7dd3fc;
  background: rgba(14, 165, 233, 0.15);
}

.connection-pill {
  display: flex;
  height: 30px;
  align-items: center;
  gap: 7px;
  padding: 0 10px;
  border: 1px solid #e2e8f0;
  border-radius: 999px;
  color: #64748b;
  background: #f8fafc;
  font-size: 12px;
}

.connection-pill i,
.flow-legend i {
  width: 7px;
  height: 7px;
  flex: 0 0 auto;
  border-radius: 50%;
  background: #f59e0b;
}

.connection-pill.connected i {
  background: #22c55e;
  box-shadow: 0 0 0 3px rgba(34, 197, 94, 0.12);
}

.is-dark .connection-pill {
  border-color: #334155;
  color: #94a3b8;
  background: #172033;
}

.flow-metric {
  display: flex;
  height: 30px;
  align-items: baseline;
  gap: 5px;
  padding: 0 4px;
  color: #64748b;
  font-size: 11px;
}

.flow-metric strong {
  color: #0f172a;
  font-size: 17px;
}

.is-dark .flow-metric strong {
  color: #f8fafc;
}

.flow-canvas {
  position: relative;
  min-height: 0;
  flex: 1;
  overflow: hidden;
  background: radial-gradient(circle at 18% 8%, rgba(14, 165, 233, 0.08), transparent 28%), #f5f7fa;
}

.is-dark .flow-canvas {
  background: radial-gradient(circle at 18% 8%, rgba(14, 165, 233, 0.1), transparent 28%), #111827;
}

.endpoint-node,
.service-node {
  box-sizing: border-box;
  border: 1px solid #d7dee8;
  background: rgba(255, 255, 255, 0.96);
  box-shadow: 0 8px 24px rgba(15, 23, 42, 0.08);
}

:deep(.vue-flow__node.selected .endpoint-node),
:deep(.vue-flow__node.selected .service-node) {
  box-shadow: 0 8px 24px rgba(15, 23, 42, 0.08);
}

.is-dark :deep(.vue-flow__node.selected .endpoint-node),
.is-dark :deep(.vue-flow__node.selected .service-node) {
  box-shadow: 0 10px 28px rgba(0, 0, 0, 0.25);
}

.endpoint-node {
  display: flex;
  width: 248px;
  min-height: 104px;
  align-items: center;
  gap: 12px;
  padding: 15px;
  border-radius: 14px;
}

.service-node {
  width: 300px;
  min-height: 140px;
  overflow: hidden;
  padding: 17px 16px 0;
  border-radius: 16px;
}

.service-node.status-running {
  box-shadow: 0 10px 30px rgba(34, 197, 94, 0.11);
}

.is-dark .endpoint-node,
.is-dark .service-node {
  border-color: #334155;
  background: rgba(23, 32, 51, 0.97);
  box-shadow: 0 10px 28px rgba(0, 0, 0, 0.25);
}

.node-icon {
  display: grid;
  width: 40px;
  height: 40px;
  flex: 0 0 auto;
  place-items: center;
  border-radius: 11px;
  color: #0369a1;
  background: #e0f2fe;
}

.host-node .node-icon {
  color: #7c3aed;
  background: #ede9fe;
}

.is-dark .node-icon {
  color: #7dd3fc;
  background: rgba(14, 165, 233, 0.14);
}

.is-dark .host-node .node-icon {
  color: #c4b5fd;
  background: rgba(139, 92, 246, 0.15);
}

.node-label {
  margin-bottom: 5px;
  color: #64748b;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.node-address {
  overflow: hidden;
  color: #0f172a;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 13px;
  font-weight: 650;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.is-dark .node-address {
  color: #f1f5f9;
}

.node-link {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin-top: 7px;
  padding: 0;
  border: 0;
  color: #0284c7;
  background: transparent;
  font: inherit;
  font-size: 11px;
  cursor: pointer;
}

.node-caption {
  margin-top: 7px;
  color: #94a3b8;
  font-size: 10px;
}

.service-heading,
.service-actions,
.service-meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.service-meta {
  margin-top: 9px;
  color: #64748b;
  font-size: 11px;
}

.node-error {
  overflow: hidden;
  margin-top: 8px;
  color: #ef4444;
  font-size: 11px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.service-actions {
  min-height: 40px;
  margin: 10px -16px 0;
  padding: 0 10px 0 16px;
  border-top: 1px solid #e8edf3;
  color: #64748b;
  font-size: 11px;
}

.is-dark .service-actions {
  border-top-color: #334155;
}

.icon-action {
  display: grid;
  width: 28px;
  height: 28px;
  place-items: center;
  border: 0;
  border-radius: 7px;
  color: #64748b;
  background: transparent;
  cursor: pointer;
}

.icon-action:hover {
  color: #0284c7;
  background: #e0f2fe;
}

.icon-action.danger:hover {
  color: #dc2626;
  background: #fee2e2;
}

.is-dark .icon-action:hover {
  color: #7dd3fc;
  background: rgba(14, 165, 233, 0.14);
}

.is-dark .icon-action.danger:hover {
  color: #fca5a5;
  background: rgba(239, 68, 68, 0.14);
}

.endpoint-node :deep(.vue-flow__handle),
.service-node :deep(.vue-flow__handle) {
  width: 9px;
  height: 9px;
  border: 2px solid #fff;
  background: #0ea5e9;
  box-shadow: 0 0 0 1px #0ea5e9;
}

.is-dark .endpoint-node :deep(.vue-flow__handle),
.is-dark .service-node :deep(.vue-flow__handle) {
  border-color: #172033;
}

.canvas-overlay {
  position: absolute;
  z-index: 4;
  inset: 0;
  display: grid;
  place-items: center;
  background: rgba(245, 247, 250, 0.72);
  backdrop-filter: blur(2px);
}

.is-dark .canvas-overlay {
  background: rgba(17, 24, 39, 0.72);
}

.flow-legend {
  position: absolute;
  right: 14px;
  bottom: 14px;
  z-index: 3;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 7px 10px;
  border: 1px solid #e2e8f0;
  border-radius: 9px;
  color: #64748b;
  background: rgba(255, 255, 255, 0.88);
  font-size: 10px;
  backdrop-filter: blur(8px);
}

.flow-legend span {
  display: flex;
  align-items: center;
  gap: 5px;
}

.flow-legend i.running {
  background: #22c55e;
}

.flow-legend i.stopped {
  background: #94a3b8;
}

.flow-legend i.error {
  background: #ef4444;
}

.is-dark .flow-legend {
  border-color: #334155;
  color: #94a3b8;
  background: rgba(23, 32, 51, 0.88);
}

:deep(.vue-flow__edge.animated path) {
  animation-duration: 0.8s;
}

:deep(.vue-flow__controls) {
  overflow: hidden;
  border: 1px solid #dbe2ea;
  border-radius: 9px;
  box-shadow: 0 5px 18px rgba(15, 23, 42, 0.08);
}

.is-dark :deep(.vue-flow__controls) {
  border-color: #334155;
}

.is-dark :deep(.vue-flow__controls-button) {
  border-bottom-color: #334155;
  color: #f1f5f9;
  background: #1e293b;
}

.is-dark :deep(.vue-flow__controls-button:hover) {
  color: #ffffff;
  background: #334155;
}

.is-dark :deep(.vue-flow__controls-button svg) {
  fill: currentColor;
  stroke: currentColor;
}

.is-dark :deep(.vue-flow__controls-button:disabled) {
  color: #64748b;
  background: #172033;
}

@media (max-width: 760px) {
  .flow-header {
    align-items: flex-start;
    padding: 12px 14px;
  }

  .flow-header > div:last-child {
    max-width: 190px;
  }

  .connection-pill,
  .flow-metric {
    display: none;
  }

  .flow-canvas {
    min-height: 420px;
  }
}
</style>

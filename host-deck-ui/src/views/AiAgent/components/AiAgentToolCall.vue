<script setup lang="ts">
import { computed, ref } from 'vue'
import { Check, CircleAlert, Clipboard, Hand, LoaderCircle, X } from '@lucide/vue'
import type { AiAgentToolCall } from '@/stores/ai-agent'

const props = defineProps<{
  tool: AiAgentToolCall
}>()

const emit = defineEmits<{
  approve: [callId: string]
  reject: [callId: string]
}>()

const modalVisible = ref(false)
const outputQuery = ref('')
const copied = ref(false)

const statusLabel = computed(() => {
  if (props.tool.status === 'pending') return '等待批准'
  if (props.tool.status === 'running') return '执行中'
  if (props.tool.status === 'success') return '已完成'
  if (props.tool.status === 'rejected') return '已拒绝'
  if (props.tool.status === 'expired') return '审批已过期'
  if (props.tool.status === 'cancelled') return '已取消'
  return '失败'
})

const argumentsText = computed(() => {
  if (typeof props.tool.arguments === 'string') return props.tool.arguments
  return JSON.stringify(props.tool.arguments ?? {}, null, 2)
})
const isMcpTool = computed(() => props.tool.name.startsWith('mcp_'))
const toolLabel = computed(() => {
  const labels: Record<string, string> = {
    apply_patch: '应用远程补丁',
    file_read: '读取远程文件',
    file_write: '写入远程文件',
    process_list: '读取进程列表',
    shell_execute: '执行远程命令',
    system_status: '读取系统状态',
  }
  return labels[props.tool.name] ?? (isMcpTool.value ? props.tool.summary : props.tool.name)
})
const outputText = computed(() => {
  const result = props.tool.result
  if (!result) return ''
  const sections = [result.content]
  if (result.stderr) sections.push(`stderr:\n${result.stderr}`)
  if (result.diff) sections.push(`diff:\n${result.diff}`)
  const structuredText =
    result.structured === undefined ? '' : JSON.stringify(result.structured, null, 2)
  if (
    structuredText &&
    !result.content.includes(structuredText) &&
    !structuredText.includes(result.content)
  ) {
    sections.push(`structured:\n${JSON.stringify(result.structured, null, 2)}`)
  }
  return sections.filter(Boolean).join('\n\n')
})
const inlineOutput = computed(() => {
  const value = outputText.value.trim()
  if (!value) return ''
  const lines = value.split('\n')
  if (lines.length > 5) return `${lines.slice(0, 5).join('\n')}\n…`
  return value.length > 360 ? `${value.slice(0, 360)}…` : value
})
const approvalPreview = computed(() => {
  const args = props.tool.arguments
  if (!args || typeof args !== 'object' || Array.isArray(args)) return ''
  const record = args as Record<string, unknown>
  if (typeof record.command === 'string') {
    return `命令：${record.command}${typeof record.cwd === 'string' ? `\n目录：${record.cwd}` : ''}`
  }
  if (typeof record.path === 'string') return `路径：${record.path}`
  if (typeof record.patch === 'string') {
    const lines = record.patch.split('\n')
    return `补丁：${lines.slice(0, 4).join('\n')}${lines.length > 4 ? '\n…' : ''}`
  }
  return JSON.stringify(record, null, 2)
})
const filteredOutput = computed(() => {
  const query = outputQuery.value.trim().toLocaleLowerCase()
  if (!query) return outputText.value
  return outputText.value
    .split('\n')
    .filter((line) => line.toLocaleLowerCase().includes(query))
    .join('\n')
})

function openModal() {
  outputQuery.value = ''
  copied.value = false
  modalVisible.value = true
}

async function copyOutput() {
  if (!outputText.value || !navigator.clipboard) return
  await navigator.clipboard.writeText(outputText.value)
  copied.value = true
  window.setTimeout(() => (copied.value = false), 1200)
}
</script>

<template>
  <section
    class="agent-tool"
    :class="[
      `agent-tool-${tool.status}`,
      {
        'agent-tool-approval': tool.approvalPending,
      },
    ]"
    :aria-label="`${tool.name}: ${statusLabel}`"
  >
    <template v-if="tool.approvalPending">
      <button
        type="button"
        class="agent-approval-detail"
        aria-haspopup="dialog"
        :aria-expanded="modalVisible"
        @click="openModal"
      >
        <span class="agent-approval-kind">
          <Hand :size="13" aria-hidden="true" />
          <span>{{ isMcpTool ? 'MCP 权限申请' : '权限申请' }}</span>
        </span>
        <strong class="agent-approval-question">允许 AI Agent 执行此工具？</strong>
        <span class="agent-approval-summary">{{ toolLabel }}</span>
        <pre v-if="approvalPreview" class="agent-approval-preview">{{ approvalPreview }}</pre>
      </button>
      <div class="agent-approval-footer">
        <div class="agent-tool-actions">
          <NButton
            size="small"
            secondary
            :disabled="tool.submitting"
            aria-label="拒绝权限申请"
            @click="emit('reject', tool.callId)"
          >
            拒绝
            <kbd>Esc</kbd>
          </NButton>
          <NButton
            size="small"
            type="primary"
            :loading="tool.submitting"
            aria-label="允许一次"
            @click="emit('approve', tool.callId)"
          >
            允许一次
          </NButton>
        </div>
      </div>
    </template>

    <template v-else>
      <button
        type="button"
        class="agent-tool-heading"
        aria-haspopup="dialog"
        :aria-expanded="modalVisible"
        @click="openModal"
      >
        <span class="agent-tool-status" aria-hidden="true">
          <LoaderCircle v-if="tool.status === 'running'" :size="13" class="agent-spin" />
          <Check v-else-if="tool.status === 'success'" :size="13" />
          <X v-else-if="tool.status === 'rejected'" :size="13" />
          <CircleAlert v-else :size="13" />
        </span>
        <span class="agent-tool-copy">
          <strong class="agent-tool-label">{{ statusLabel }}</strong>
          <span class="agent-tool-summary">{{ toolLabel }}</span>
        </span>
      </button>
      <pre v-if="inlineOutput" class="agent-tool-inline-output">{{ inlineOutput }}</pre>
    </template>

    <NModal
      v-model:show="modalVisible"
      preset="card"
      title="工具调用详情"
      style="width: min(640px, calc(100vw - 32px))"
    >
      <div class="agent-tool-modal-body app-scrollbar">
        <header class="agent-tool-modal-header">
          <strong>{{ toolLabel }}</strong>
          <span>{{ statusLabel }}</span>
        </header>
        <p class="agent-tool-modal-summary">{{ toolLabel }}</p>

        <section v-if="tool.arguments !== undefined" class="agent-tool-modal-section">
          <h3>参数</h3>
          <pre class="agent-tool-arguments">{{ argumentsText }}</pre>
        </section>

        <section v-if="tool.result" class="agent-tool-modal-section">
          <div class="agent-tool-result-heading">
            <h3>结果</h3>
            <button
              type="button"
              class="agent-tool-copy-action"
              :aria-label="copied ? '已复制工具结果' : '复制工具结果'"
              @click="copyOutput"
            >
              <Check v-if="copied" :size="13" />
              <Clipboard v-else :size="13" />
              {{ copied ? '已复制' : '复制结果' }}
            </button>
          </div>
          <div class="agent-tool-result-meta">
            <span v-if="tool.result.path">{{ tool.result.path }}</span>
            <span v-if="tool.result.operation">{{ tool.result.operation }}</span>
            <span v-if="tool.result.mcpServer">{{ tool.result.mcpServer }}</span>
            <span v-if="tool.result.mcpTool">{{ tool.result.mcpTool }}</span>
            <span v-if="tool.result.exitCode != null">退出码 {{ tool.result.exitCode }}</span>
            <span v-if="tool.result.durationMs != null">{{ tool.result.durationMs }} ms</span>
            <span v-if="tool.result.truncated">已截断</span>
            <span v-if="tool.result.changed != null">
              {{ tool.result.changed ? '已修改' : '未修改' }}
            </span>
          </div>
          <input
            v-model="outputQuery"
            class="agent-tool-search"
            type="search"
            placeholder="搜索工具输出"
            aria-label="搜索工具输出"
          />
          <pre class="agent-tool-arguments">{{ filteredOutput }}</pre>
        </section>
        <p v-else class="agent-tool-modal-empty">暂无结果</p>
      </div>
    </NModal>
  </section>
</template>

<style scoped>
.agent-tool {
  width: min(100%, 680px);
  margin: 6px 0;
  padding: 0;
  border: 0;
  border-radius: var(--app-radius-item);
  overflow: hidden;
  background: transparent;
}

.agent-tool-pending {
  color: #d97706;
}

.agent-tool-running {
  color: var(--agent-muted);
}

.agent-tool-success {
  color: #16a34a;
}

.agent-tool-error,
.agent-tool-rejected,
.agent-tool-expired,
.agent-tool-cancelled {
  color: #dc2626;
}

.agent-tool-cancelled {
  color: #d97706;
}

.agent-tool-approval {
  padding: 12px 14px 10px;
  border: 1px solid var(--agent-border);
  color: var(--agent-text);
  background: var(--agent-elevated);
}

.agent-approval-kind {
  display: flex;
  align-items: center;
  gap: 6px;
  color: var(--agent-muted);
  font-size: 10px;
  font-weight: 600;
}

.agent-approval-detail {
  display: block;
  width: 100%;
  padding: 0;
  border: 0;
  color: inherit;
  background: transparent;
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.agent-approval-question {
  display: block;
  margin-top: 7px;
  font-size: 13px;
  font-weight: 600;
  line-height: 1.35;
}

.agent-approval-summary {
  display: block;
  margin: 3px 0 0;
  color: var(--agent-muted);
  font-size: 11px;
  line-height: 1.45;
}

.agent-approval-preview {
  max-height: 92px;
  margin: 8px 0 0;
  overflow: auto;
  padding: 7px 9px;
  border-radius: var(--app-radius-control);
  color: var(--agent-text);
  background: var(--agent-code-bg);
  white-space: pre-wrap;
  word-break: break-word;
  font:
    10px/1.5 'Maple Mono',
    monospace;
}

.agent-approval-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 10px;
  margin-top: 10px;
}

.agent-tool-heading {
  display: flex;
  align-items: center;
  width: 100%;
  gap: 7px;
  padding: 4px 8px;
  border: 0;
  color: inherit;
  background: transparent;
  font: inherit;
  text-align: left;
  cursor: pointer;
}

.agent-tool-heading:hover {
  background: var(--agent-hover);
}

.agent-tool-status {
  display: grid;
  width: 18px;
  height: 18px;
  flex: 0 0 auto;
  place-items: center;
  border-radius: var(--app-radius-control);
  color: currentColor;
}

.agent-tool-copy-action {
  display: flex;
  align-items: center;
  flex: 0 0 auto;
  gap: 5px;
  padding: 0;
  border: 0;
  color: inherit;
  background: transparent;
  font: inherit;
  font-size: 11px;
  opacity: 0.66;
  cursor: pointer;
}

.agent-tool-copy-action:hover {
  opacity: 1;
}

.agent-tool-summary {
  min-width: 0;
  overflow: hidden;
  color: var(--agent-muted);
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 11px;
}

.agent-tool-inline-output {
  max-height: 118px;
  margin: 2px 8px 6px 33px;
  overflow: hidden;
  padding: 6px 8px;
  border-left: 2px solid var(--agent-border);
  color: var(--agent-muted);
  white-space: pre-wrap;
  word-break: break-word;
  font:
    10px/1.5 'Maple Mono',
    monospace;
}

.agent-tool-label {
  flex: 0 0 auto;
  color: currentColor;
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0;
}

.agent-tool-arguments {
  max-height: 360px;
  margin: 8px 0 0;
  overflow: auto;
  padding: 8px 10px;
  border-radius: var(--app-radius-control);
  background: var(--agent-code-bg);
  white-space: pre-wrap;
  word-break: break-word;
  user-select: text;
  font:
    11px/1.55 'Maple Mono',
    monospace;
}

.agent-tool-copy {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  min-width: 0;
  padding: 0;
  border: 0;
  color: inherit;
  background: transparent;
  font-size: 11px;
}

.agent-tool-result-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin: 8px 0 5px;
  color: var(--agent-muted);
  font-size: 10px;
}

.agent-tool-search {
  box-sizing: border-box;
  width: 100%;
  height: 25px;
  margin-bottom: 5px;
  padding: 0 7px;
  border: 1px solid var(--agent-border);
  border-radius: var(--app-radius-control);
  outline: 0;
  color: var(--agent-text);
  background: var(--agent-elevated);
  font-size: 11px;
}

.agent-tool-actions {
  display: flex;
  flex: 0 0 auto;
  justify-content: flex-end;
  gap: 5px;
}

.agent-tool-actions :deep(.n-button) {
  min-height: 24px;
  padding: 0 8px;
  font-size: 11px;
}

.agent-tool-actions kbd {
  margin-left: 5px;
  padding: 1px 4px;
  border-radius: 4px;
  color: var(--agent-muted);
  background: var(--agent-hover);
  font: inherit;
  font-size: 9px;
}

.agent-tool-modal-body {
  max-height: min(65vh, 620px);
  overflow: auto;
  padding-right: 2px;
  color: var(--agent-text);
}

.agent-tool-modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.agent-tool-modal-header strong {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 14px;
}

.agent-tool-modal-header span {
  flex: 0 0 auto;
  color: var(--agent-muted);
  font-size: 11px;
}

.agent-tool-modal-summary {
  margin: 4px 0 0;
  color: var(--agent-muted);
  font-size: 11px;
  line-height: 1.45;
}

.agent-tool-modal-section {
  margin-top: 14px;
}

.agent-tool-modal-section h3,
.agent-tool-result-heading h3 {
  margin: 0;
  color: var(--agent-muted);
  font-size: 11px;
  font-weight: 600;
}

.agent-tool-result-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.agent-tool-modal-empty {
  margin: 14px 0 0;
  color: var(--agent-muted);
  font-size: 11px;
}

@media (max-width: 520px) {
  .agent-approval-footer {
    align-items: flex-start;
    flex-wrap: wrap;
  }

  .agent-tool-actions {
    margin-left: auto;
  }
}

.agent-spin {
  animation: agent-spin 1s linear infinite;
}

@keyframes agent-spin {
  to {
    transform: rotate(360deg);
  }
}
</style>

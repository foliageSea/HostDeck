<script setup lang="ts">
import { computed, ref } from 'vue'
import { Check, ChevronDown, CircleAlert, Clipboard, Hand, LoaderCircle, X } from '@lucide/vue'
import type { AiAgentToolCall } from '@/stores/ai-agent'

const props = defineProps<{
  tool: AiAgentToolCall
}>()

const emit = defineEmits<{
  approve: [callId: string]
  reject: [callId: string]
}>()

const expanded = ref(false)
const outputQuery = ref('')
const copied = ref(false)

const statusLabel = computed(() => {
  if (props.tool.status === 'pending') return '等待批准'
  if (props.tool.status === 'running') return '执行中'
  if (props.tool.status === 'success') return '已完成'
  if (props.tool.status === 'rejected') return '已拒绝'
  return '失败'
})

const argumentsText = computed(() => {
  if (typeof props.tool.arguments === 'string') return props.tool.arguments
  return JSON.stringify(props.tool.arguments ?? {}, null, 2)
})
const isMcpTool = computed(() => props.tool.name.startsWith('mcp_'))
const outputText = computed(() => {
  const result = props.tool.result
  if (!result) return ''
  const sections = [result.content]
  if (result.stderr) sections.push(`stderr:\n${result.stderr}`)
  if (result.structured !== undefined) {
    sections.push(`structured:\n${JSON.stringify(result.structured, null, 2)}`)
  }
  return sections.filter(Boolean).join('\n\n')
})
const filteredOutput = computed(() => {
  const query = outputQuery.value.trim().toLocaleLowerCase()
  if (!query) return outputText.value
  return outputText.value
    .split('\n')
    .filter((line) => line.toLocaleLowerCase().includes(query))
    .join('\n')
})

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
      <div class="agent-approval-kind">
        <Hand :size="13" aria-hidden="true" />
        <span>{{ isMcpTool ? 'MCP 权限申请' : '权限申请' }}</span>
      </div>
      <strong class="agent-approval-question">允许 AI Agent 执行此工具？</strong>
      <p class="agent-approval-summary">{{ tool.summary }}</p>
      <pre v-if="expanded" class="agent-tool-arguments">{{ argumentsText }}</pre>
      <div class="agent-approval-footer">
        <button
          type="button"
          class="agent-tool-disclosure"
          :aria-expanded="expanded"
          @click="expanded = !expanded"
        >
          <ChevronDown :size="13" :class="{ 'rotate-180': expanded }" />
          {{ expanded ? '收起参数' : '查看参数' }}
        </button>
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

    <div v-else class="agent-tool-heading">
      <span class="agent-tool-status" aria-hidden="true">
        <LoaderCircle v-if="tool.status === 'running'" :size="13" class="agent-spin" />
        <Check v-else-if="tool.status === 'success'" :size="13" />
        <X v-else-if="tool.status === 'rejected'" :size="13" />
        <CircleAlert v-else :size="13" />
      </span>
      <div class="agent-tool-copy">
        <strong class="agent-tool-label">{{ statusLabel }}</strong>
        <span class="agent-tool-summary">{{ tool.summary }}</span>
      </div>
    </div>
    <div v-if="!tool.approvalPending && (tool.arguments !== undefined || tool.result)" class="agent-tool-details">
      <button
        type="button"
        class="agent-tool-disclosure"
        :aria-expanded="expanded"
        @click="expanded = !expanded"
      >
        <ChevronDown :size="13" :class="{ 'rotate-180': expanded }" />
        {{ expanded ? '收起详情' : '查看参数与结果' }}
      </button>
      <button
        v-if="expanded && tool.result"
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
    <template v-if="expanded && !tool.approvalPending">
      <pre v-if="tool.arguments !== undefined" class="agent-tool-arguments">参数
{{ argumentsText }}</pre>
      <div v-if="tool.result" class="agent-tool-result">
        <div class="agent-tool-result-meta">
          <span v-if="tool.result.exitCode != null">退出码 {{ tool.result.exitCode }}</span>
          <span v-if="tool.result.durationMs != null">{{ tool.result.durationMs }} ms</span>
          <span v-if="tool.result.truncated">已截断</span>
          <span v-if="tool.result.changed != null">{{ tool.result.changed ? '已修改' : '未修改' }}</span>
        </div>
        <input
          v-model="outputQuery"
          class="agent-tool-search"
          type="search"
          placeholder="搜索工具输出"
          aria-label="搜索工具输出"
        />
        <pre class="agent-tool-arguments">{{ filteredOutput }}</pre>
      </div>
    </template>
  </section>
</template>

<style scoped>
.agent-tool {
  width: min(100%, 680px);
  margin: 6px 0;
  padding: 4px 8px;
  border: 0;
  border-radius: var(--app-radius-item);
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
.agent-tool-rejected {
  color: #dc2626;
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

.agent-approval-question {
  display: block;
  margin-top: 7px;
  font-size: 13px;
  font-weight: 600;
  line-height: 1.35;
}

.agent-approval-summary {
  margin: 3px 0 0;
  color: var(--agent-muted);
  font-size: 11px;
  line-height: 1.45;
}

.agent-approval-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin-top: 10px;
}

.agent-tool-heading {
  display: flex;
  align-items: center;
  gap: 7px;
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

.agent-tool-label {
  flex: 0 0 auto;
  color: currentColor;
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0;
}

.agent-tool-disclosure {
  display: flex;
  align-items: center;
  gap: 5px;
  padding: 0;
  border: 0;
  color: inherit;
  background: transparent;
  font-size: 11px;
  opacity: 0.66;
  cursor: pointer;
}

.agent-tool-arguments {
  max-height: 120px;
  margin: 8px 0 0;
  overflow: auto;
  padding: 6px 8px;
  border-radius: var(--app-radius-control);
  background: var(--agent-code-bg);
  white-space: pre-wrap;
  word-break: break-word;
  user-select: text;
  font:
    11px/1.55 'Maple Mono',
    monospace;
}

.agent-tool-details {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-top: 6px;
}

.agent-tool-copy {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 0;
  border: 0;
  color: inherit;
  background: transparent;
  font-size: 11px;
  cursor: pointer;
}

.agent-tool-result {
  min-width: 0;
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

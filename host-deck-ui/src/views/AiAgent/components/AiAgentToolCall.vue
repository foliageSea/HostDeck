<script setup lang="ts">
import { computed, ref } from 'vue'
import { Check, ChevronDown, CircleAlert, Hand, LoaderCircle, X } from '@lucide/vue'
import type { AiAgentToolCall } from '@/stores/ai-agent'

const props = defineProps<{
  tool: AiAgentToolCall
}>()

const emit = defineEmits<{
  approve: [callId: string]
  reject: [callId: string]
}>()

const expanded = ref(false)

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
</script>

<template>
  <section
    class="agent-tool"
    :class="[`agent-tool-${tool.status}`, { 'agent-tool-approval': tool.approvalPending }]"
    :aria-label="`${tool.name}: ${statusLabel}`"
  >
    <template v-if="tool.approvalPending">
      <div class="agent-approval-kind">
        <Hand :size="13" aria-hidden="true" />
        <span>权限申请</span>
      </div>
      <strong class="agent-approval-question">允许 AI Agent 使用 {{ tool.name }}？</strong>
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

.agent-tool-copy {
  display: flex;
  min-width: 0;
  align-items: baseline;
  flex: 1;
  gap: 7px;
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

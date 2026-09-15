<script setup lang="ts">
import { computed, ref } from 'vue'
import { Check, ChevronDown, CircleAlert, LoaderCircle, ShieldQuestion, X } from '@lucide/vue'
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
  <section class="agent-tool" :class="`agent-tool-${tool.status}`">
    <div class="agent-tool-heading">
      <span class="agent-tool-status" aria-hidden="true">
        <LoaderCircle v-if="tool.status === 'running'" :size="15" class="agent-spin" />
        <ShieldQuestion v-else-if="tool.status === 'pending'" :size="15" />
        <Check v-else-if="tool.status === 'success'" :size="15" />
        <X v-else-if="tool.status === 'rejected'" :size="15" />
        <CircleAlert v-else :size="15" />
      </span>
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-2">
          <strong class="truncate text-[13px]">{{ tool.name }}</strong>
          <span class="agent-tool-label">{{ statusLabel }}</span>
        </div>
        <p class="m-0 mt-1 break-words text-[12px] opacity-75">{{ tool.summary }}</p>
      </div>
    </div>

    <button
      v-if="tool.approvalPending"
      type="button"
      class="agent-tool-disclosure"
      :aria-expanded="expanded"
      @click="expanded = !expanded"
    >
      <ChevronDown :size="14" :class="{ 'rotate-180': expanded }" />
      {{ expanded ? '收起参数' : '查看参数' }}
    </button>
    <pre v-if="tool.approvalPending && expanded" class="agent-tool-arguments">{{
      argumentsText
    }}</pre>

    <div v-if="tool.approvalPending" class="mt-3 flex justify-end gap-2">
      <NButton
        size="small"
        secondary
        type="error"
        :disabled="tool.submitting"
        @click="emit('reject', tool.callId)"
      >
        拒绝
      </NButton>
      <NButton
        size="small"
        type="primary"
        :loading="tool.submitting"
        @click="emit('approve', tool.callId)"
      >
        批准
      </NButton>
    </div>
  </section>
</template>

<style scoped>
.agent-tool {
  width: min(100%, 680px);
  margin: 10px 0;
  padding: 11px 13px;
  border: 1px solid var(--agent-border);
  border-left: 3px solid var(--agent-muted);
  border-radius: var(--app-radius-item);
  background: var(--agent-tool-bg);
}

.agent-tool-pending {
  border-left-color: #d97706;
}

.agent-tool-running {
  border-left-color: var(--app-primary-color);
}

.agent-tool-success {
  border-left-color: #16a34a;
}

.agent-tool-error,
.agent-tool-rejected {
  border-left-color: #dc2626;
}

.agent-tool-heading {
  display: flex;
  align-items: flex-start;
  gap: 9px;
}

.agent-tool-status {
  display: grid;
  width: 24px;
  height: 24px;
  flex: 0 0 auto;
  place-items: center;
  border-radius: var(--app-radius-control);
  background: var(--agent-hover);
}

.agent-tool-label {
  flex: 0 0 auto;
  font-size: 10px;
  letter-spacing: 0;
  opacity: 0.58;
}

.agent-tool-disclosure {
  display: flex;
  align-items: center;
  gap: 5px;
  margin-top: 10px;
  padding: 0;
  border: 0;
  color: inherit;
  background: transparent;
  font-size: 11px;
  opacity: 0.66;
  cursor: pointer;
}

.agent-tool-arguments {
  max-height: 190px;
  margin: 8px 0 0;
  overflow: auto;
  padding: 10px;
  border-radius: var(--app-radius-control);
  background: var(--agent-code-bg);
  white-space: pre-wrap;
  word-break: break-word;
  user-select: text;
  font:
    11px/1.55 'Maple Mono',
    monospace;
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

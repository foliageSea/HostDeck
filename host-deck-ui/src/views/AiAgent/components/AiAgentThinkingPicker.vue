<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { Brain, ChevronDown, RotateCcw } from '@lucide/vue'
import type { AiAgentThinkingLevel } from '@/api/ai-agent'

const props = defineProps<{
  modelName: string
  provider: string
  levels: AiAgentThinkingLevel[]
  value: AiAgentThinkingLevel | 'default'
  disabled?: boolean
}>()
const emit = defineEmits<{
  'update:value': [value: AiAgentThinkingLevel | 'default']
}>()
const open = ref(false)
const labels: Record<AiAgentThinkingLevel | 'default', string> = {
  default: '默认',
  off: '关闭',
  minimal: '极低',
  low: '低',
  medium: '中',
  high: '高',
  xhigh: '超高',
  max: '最高',
}
const options = computed(() => ['default' as const, ...props.levels])
const selectedIndex = computed(() => Math.max(0, options.value.indexOf(props.value)))
const progress = computed(() => `${(selectedIndex.value / (options.value.length - 1)) * 100}%`)

function select(event: Event) {
  const level = options.value[Number((event.target as HTMLInputElement).value)]
  if (!props.disabled && level) emit('update:value', level)
}

watch(
  () => [props.disabled, props.modelName, props.provider],
  () => {
    open.value = false
  },
)
</script>

<template>
  <NPopover
    v-model:show="open"
    trigger="click"
    placement="top-start"
    :show-arrow="false"
    :disabled="disabled"
    :raw="true"
  >
    <template #trigger>
      <button
        type="button"
        class="agent-thinking-trigger"
        :disabled="disabled"
        :aria-expanded="open"
        aria-label="选择思考强度"
      >
        <Brain :size="13" />
        <span>{{ value === 'default' ? '思考强度' : `思考：${labels[value]}` }}</span>
        <ChevronDown :size="11" />
      </button>
    </template>
    <div class="agent-thinking-picker">
      <div class="agent-thinking-level" aria-live="polite">{{ labels[value] }}</div>
      <button
        type="button"
        class="agent-thinking-reset"
        aria-label="恢复默认思考强度"
        title="恢复默认"
        :disabled="disabled || value === 'default'"
        @click="emit('update:value', 'default')"
      >
        <RotateCcw :size="16" />
      </button>
      <div class="agent-thinking-model" :title="`${modelName} · ${provider}`">
        {{ modelName }} · {{ provider }}
      </div>
      <div class="agent-thinking-slider" :style="{ '--thinking-progress': progress }">
        <div class="agent-thinking-track" aria-hidden="true">
          <span v-for="option in options" :key="option" />
        </div>
        <input
          type="range"
          min="0"
          :max="options.length - 1"
          step="1"
          :value="selectedIndex"
          :disabled="disabled"
          aria-label="思考强度"
          :aria-valuetext="labels[value]"
          @input="select"
        />
      </div>
    </div>
  </NPopover>
</template>

<style scoped>
.agent-thinking-trigger {
  display: inline-flex;
  height: 25px;
  align-items: center;
  gap: 5px;
  padding: 0 8px;
  border: 0;
  border-radius: var(--app-radius-control);
  color: var(--agent-muted);
  background: var(--agent-hover);
  font-size: 12px;
  line-height: 1;
  cursor: pointer;
}

.agent-thinking-trigger:hover:not(:disabled) {
  color: var(--app-primary-color);
  background: var(--app-primary-soft);
}

.agent-thinking-trigger:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-thinking-picker {
  position: relative;
  width: min(310px, calc(100vw - 48px));
  box-sizing: border-box;
  padding: 17px 18px 19px;
  border: 1px solid var(--n-border-color, rgba(128, 128, 128, 0.24));
  border-radius: 20px;
  color: var(--n-text-color, #555);
  background: var(--n-color, #fff);
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.16);
}

.agent-thinking-level {
  color: var(--app-primary-color);
  text-align: center;
  font-size: 17px;
  font-weight: 600;
  line-height: 24px;
}

.agent-thinking-reset {
  position: absolute;
  top: 16px;
  right: 15px;
  display: grid;
  width: 26px;
  height: 26px;
  place-items: center;
  padding: 0;
  border: 0;
  border-radius: 50%;
  color: inherit;
  background: transparent;
  opacity: 0.6;
  cursor: pointer;
}

.agent-thinking-reset:hover:not(:disabled) {
  background: rgba(128, 128, 128, 0.14);
  opacity: 1;
}

.agent-thinking-reset:disabled {
  opacity: 0.3;
  cursor: default;
}

.agent-thinking-model {
  overflow: hidden;
  margin: 2px 0 20px;
  text-align: center;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 13px;
  opacity: 0.65;
}

.agent-thinking-slider {
  position: relative;
  height: 30px;
}

.agent-thinking-track {
  position: absolute;
  inset: 2px 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 13px;
  border-radius: 20px;
  background: linear-gradient(
    to right,
    var(--app-primary-color) 0%,
    var(--app-primary-color) var(--thinking-progress),
    rgba(128, 128, 128, 0.22) var(--thinking-progress),
    rgba(128, 128, 128, 0.22) 100%
  );
  box-shadow: inset 0 0 0 1px rgba(128, 128, 128, 0.15);
}

.agent-thinking-track span {
  width: 4px;
  height: 4px;
  border-radius: 50%;
  background: currentColor;
  opacity: 0.4;
}

.agent-thinking-slider input {
  position: relative;
  display: block;
  width: 100%;
  height: 30px;
  margin: 0;
  appearance: none;
  -webkit-appearance: none;
  border-radius: 20px;
  background: transparent;
  cursor: pointer;
}

.agent-thinking-slider input::-webkit-slider-thumb {
  width: 30px;
  height: 30px;
  appearance: none;
  -webkit-appearance: none;
  border: 0;
  border-radius: 50%;
  background: #fff;
  box-shadow: 0 1px 5px rgba(0, 0, 0, 0.15);
}

.agent-thinking-slider input::-moz-range-thumb {
  width: 30px;
  height: 30px;
  border: 0;
  border-radius: 50%;
  background: #fff;
  box-shadow: 0 1px 5px rgba(0, 0, 0, 0.15);
}

.agent-thinking-slider input:focus-visible,
.agent-thinking-trigger:focus-visible,
.agent-thinking-reset:focus-visible {
  outline: 2px solid var(--app-primary-color);
  outline-offset: 3px;
}
</style>

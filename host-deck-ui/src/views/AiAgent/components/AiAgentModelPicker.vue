<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { Bot, Check, ChevronDown, ChevronLeft, ChevronRight, RotateCcw } from '@lucide/vue'
import type { AiAgentThinkingLevel } from '@/api/ai-agent'

interface ModelOption {
  id: string
  key: string
  label: string
  provider: string
  hasCredentials: boolean
}

interface ModelGroup {
  models: ModelOption[]
  provider: string
}

const props = defineProps<{
  modelName: string
  provider: string
  groups: ModelGroup[]
  activeProvider?: string
  activeModel?: string
  levels: AiAgentThinkingLevel[]
  thinking: AiAgentThinkingLevel | 'default'
  switching?: boolean
  disabled?: boolean
}>()

const emit = defineEmits<{
  select: [provider: string, model: string]
  'update:thinking': [level: AiAgentThinkingLevel | 'default']
}>()

type PickerView = 'root' | 'models' | 'thinking'

const open = defineModel<boolean>('show', { default: false })
const view = ref<PickerView>('root')
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

const locked = computed(() => Boolean(props.disabled || props.switching))
const canAdjustThinking = computed(() => props.levels.length > 0)
const thinkingLabel = computed(() => labels[props.thinking])
const thinkingOptions = computed(() => ['default' as const, ...props.levels])
const selectedThinkingIndex = computed(() =>
  Math.max(0, thinkingOptions.value.indexOf(props.thinking)),
)
const thinkingProgress = computed(
  () => `${(selectedThinkingIndex.value / Math.max(1, thinkingOptions.value.length - 1)) * 100}%`,
)

function isActive(model: ModelOption) {
  return props.activeProvider === model.provider && props.activeModel === model.id
}

function chooseModel(model: ModelOption) {
  if (locked.value || !model.hasCredentials) return
  emit('select', model.provider, model.id)
  open.value = false
}

function chooseThinking(event: Event) {
  if (locked.value) return
  const level = thinkingOptions.value[Number((event.target as HTMLInputElement).value)]
  if (level) emit('update:thinking', level)
}

function resetThinking() {
  if (!locked.value) emit('update:thinking', 'default')
}

watch(open, (value) => {
  if (value) view.value = 'root'
})

watch(locked, (value) => {
  if (value) open.value = false
})
</script>

<template>
  <NPopover
    v-model:show="open"
    trigger="click"
    placement="top-end"
    :show-arrow="false"
    :disabled="disabled"
  >
    <template #trigger>
      <button
        type="button"
        class="agent-model-trigger"
        :disabled="disabled"
        :aria-expanded="open"
        aria-label="选择模型和推理等级"
      >
        <span class="agent-model-trigger-name">{{ modelName }}</span>
        <span v-if="canAdjustThinking" class="agent-model-trigger-thinking">
          {{ thinkingLabel }}
        </span>
        <ChevronDown :size="12" />
      </button>
    </template>

    <div class="agent-model-picker">
      <template v-if="view === 'root'">
        <button
          type="button"
          class="agent-model-row"
          :disabled="groups.length === 0"
          @click="view = 'models'"
        >
          <span class="agent-model-row-label">模型</span>
          <span class="agent-model-row-value">{{ modelName }}</span>
          <ChevronRight :size="14" />
        </button>
        <button
          v-if="canAdjustThinking"
          type="button"
          class="agent-model-row"
          @click="view = 'thinking'"
        >
          <span class="agent-model-row-label">推理等级</span>
          <span class="agent-model-row-value">{{ thinkingLabel }}</span>
          <ChevronRight :size="14" />
        </button>
      </template>

      <template v-else-if="view === 'models'">
        <button type="button" class="agent-model-back" @click="view = 'root'">
          <ChevronLeft :size="14" />
          模型
        </button>
        <div class="agent-model-list app-scrollbar app-scrollbar-compact">
          <div v-for="group in groups" :key="group.provider" class="agent-model-group">
            <div class="agent-model-group-heading">
              <span>{{ group.provider }}</span>
              <span>{{ group.models.length }} 个模型</span>
            </div>
            <button
              v-for="model in group.models"
              :key="model.key"
              type="button"
              class="agent-model-option"
              :aria-pressed="isActive(model)"
              :disabled="locked || !model.hasCredentials"
              @click="chooseModel(model)"
            >
              <Bot :size="16" />
              <span class="agent-model-copy">
                <strong>{{ model.label }}</strong>
                <span>{{ model.id }}</span>
              </span>
              <Check :size="16" :style="{ visibility: isActive(model) ? 'visible' : 'hidden' }" />
            </button>
          </div>
        </div>
      </template>

      <template v-else>
        <button type="button" class="agent-model-back" @click="view = 'root'">
          <ChevronLeft :size="14" />
          推理等级
        </button>
        <div class="agent-thinking-panel">
          <div class="agent-thinking-level" aria-live="polite">{{ thinkingLabel }}</div>
          <button
            type="button"
            class="agent-thinking-reset"
            aria-label="恢复默认推理等级"
            title="恢复默认"
            :disabled="locked || thinking === 'default'"
            @click="resetThinking"
          >
            <RotateCcw :size="16" />
          </button>
          <div class="agent-thinking-model" :title="`${modelName} · ${provider}`">
            {{ modelName }} · {{ provider }}
          </div>
          <div class="agent-thinking-slider" :style="{ '--thinking-progress': thinkingProgress }">
            <div class="agent-thinking-track" aria-hidden="true">
              <span v-for="option in thinkingOptions" :key="option" />
            </div>
            <input
              type="range"
              min="0"
              :max="thinkingOptions.length - 1"
              step="1"
              :value="selectedThinkingIndex"
              :disabled="locked"
              aria-label="推理等级"
              :aria-valuetext="thinkingLabel"
              @input="chooseThinking"
            />
          </div>
        </div>
      </template>
    </div>
  </NPopover>
</template>

<style scoped>
.agent-model-trigger {
  display: inline-flex;
  min-width: 0;
  max-width: min(260px, 46vw);
  height: 28px;
  align-items: center;
  gap: 5px;
  padding: 0 8px;
  border: 0;
  border-radius: var(--app-radius-control);
  color: var(--agent-muted, #64748b);
  background: transparent;
  font-size: 12px;
  line-height: 1;
  cursor: pointer;
}

.agent-model-trigger:hover:not(:disabled),
.agent-model-trigger[aria-expanded='true'] {
  color: var(--agent-text, #182233);
  background: var(--agent-hover, rgba(100, 116, 139, 0.09));
}

.agent-model-trigger:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-model-trigger-name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.agent-model-trigger-thinking {
  flex: 0 0 auto;
  opacity: 0.7;
}

.agent-model-picker {
  width: min(320px, calc(100vw - 32px));
  color: var(--n-text-color);
}

.agent-model-row {
  display: grid;
  width: 100%;
  grid-template-columns: auto minmax(0, 1fr) 14px;
  align-items: center;
  gap: 12px;
  padding: 9px 8px;
  border: 0;
  border-radius: var(--app-radius-item);
  color: inherit;
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.agent-model-row:hover:not(:disabled) {
  background: var(--n-color-embedded);
}

.agent-model-row:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-model-row-label {
  color: var(--n-text-color-3);
  font-size: 11px;
}

.agent-model-row-value {
  min-width: 0;
  overflow: hidden;
  text-align: right;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
  font-weight: 500;
}

.agent-model-back {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 4px;
  margin-bottom: 4px;
  padding: 5px 6px;
  border: 0;
  border-radius: var(--app-radius-control);
  color: var(--n-text-color-3);
  background: transparent;
  font-size: 11px;
  cursor: pointer;
}

.agent-model-back:hover {
  background: var(--n-color-embedded);
}

.agent-model-list {
  max-height: min(60vh, 380px);
  margin: 0 -4px;
  overflow-y: auto;
  padding: 0 4px;
}

.agent-model-group + .agent-model-group {
  margin-top: 7px;
  padding-top: 7px;
  border-top: 1px solid var(--n-border-color);
}

.agent-model-group-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 3px 8px 5px;
  color: var(--n-text-color-3);
  font-size: 10px;
  font-weight: 600;
}

.agent-model-group-heading > span:last-child {
  font-size: 9px;
  font-weight: 400;
  opacity: 0.7;
}

.agent-model-option {
  display: grid;
  width: 100%;
  grid-template-columns: 16px minmax(0, 1fr) 16px;
  align-items: center;
  gap: 10px;
  padding: 9px 8px;
  border: 0;
  border-radius: var(--app-radius-item);
  color: inherit;
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.agent-model-option:hover:not(:disabled) {
  background: var(--n-color-embedded);
}

.agent-model-option:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-model-copy {
  display: grid;
  min-width: 0;
  gap: 3px;
  font-size: 11px;
  line-height: 1.5;
}

.agent-model-copy strong {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
  font-weight: 600;
}

.agent-model-copy > span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  opacity: 0.65;
}

.agent-thinking-panel {
  position: relative;
  padding: 6px 8px 4px;
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
  top: 4px;
  right: 4px;
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
  background: var(--n-color-embedded);
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
  font-size: 12px;
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

.agent-model-trigger:focus-visible,
.agent-model-row:focus-visible,
.agent-model-back:focus-visible,
.agent-model-option:focus-visible,
.agent-thinking-slider input:focus-visible,
.agent-thinking-reset:focus-visible {
  outline: 2px solid var(--app-primary-color);
  outline-offset: 2px;
}
</style>

<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { Check, ChevronDown, ChevronLeft, ChevronRight, SquarePen, X } from '@lucide/vue'
import type { AiAgentAnswer, AiAgentQuestion } from '@/api/ai-agent'

const props = defineProps<{
  questions: AiAgentQuestion[]
  submitting?: boolean
}>()

const emit = defineEmits<{
  submit: [answers: AiAgentAnswer[]]
  skip: []
}>()

const rootRef = ref<HTMLElement | null>(null)
const customInput = ref<HTMLInputElement | null>(null)
const index = ref(0)
const collapsed = ref(false)
const selections = reactive<Record<string, string[]>>({})
const customs = reactive<Record<string, string>>({})
for (const question of props.questions) {
  selections[question.id] = []
  customs[question.id] = ''
}

const current = computed(() => props.questions[index.value]!)
const isLast = computed(() => index.value === props.questions.length - 1)

function isAnswered(question: AiAgentQuestion) {
  return (selections[question.id]?.length ?? 0) > 0 || (customs[question.id]?.trim() ?? '') !== ''
}

const canAdvance = computed(() => isAnswered(current.value))
const canSubmit = computed(() => props.questions.every(isAnswered))

function isSelected(label: string) {
  return selections[current.value.id]!.includes(label)
}

function toggleOption(label: string) {
  const question = current.value
  const selected = selections[question.id]!
  if (question.multiSelect) {
    selections[question.id] = selected.includes(label)
      ? selected.filter((item) => item !== label)
      : [...selected, label]
    return
  }
  // A single-select question has exactly one answer: a listed option or text.
  selections[question.id] = selected.includes(label) ? [] : [label]
  customs[question.id] = ''
}

function onCustomInput(value: string) {
  const question = current.value
  customs[question.id] = value
  if (!question.multiSelect && value.trim() !== '') selections[question.id] = []
}

function focusCustom() {
  void nextTick(() => customInput.value?.focus())
}

function go(offset: number) {
  const next = index.value + offset
  if (next >= 0 && next < props.questions.length) index.value = next
}

function advance() {
  if (props.submitting || !canAdvance.value) return
  if (!isLast.value) {
    go(1)
    return
  }
  if (canSubmit.value) submit()
}

function submit() {
  emit(
    'submit',
    props.questions.map((question) => {
      const custom = customs[question.id]!.trim()
      return {
        id: question.id,
        selected: [...selections[question.id]!],
        ...(custom ? { custom } : {}),
      }
    }),
  )
}

function isEditableTarget(target: EventTarget | null) {
  return (
    target instanceof HTMLElement &&
    (['INPUT', 'TEXTAREA', 'BUTTON', 'SELECT'].includes(target.tagName) || target.isContentEditable)
  )
}

function handleKeydown(event: KeyboardEvent) {
  if (event.isComposing || event.keyCode === 229) return
  if (event.ctrlKey || event.metaKey || event.altKey) return
  if (collapsed.value || isEditableTarget(event.target)) return
  const root = rootRef.value
  const target = event.target
  const owned =
    target === document.body ||
    target === document.documentElement ||
    (target instanceof Node && root?.contains(target))
  if (!owned) return
  if (event.key === 'Enter') {
    event.preventDefault()
    advance()
    return
  }
  if (!/^[1-9]$/.test(event.key)) return
  const position = Number(event.key) - 1
  const options = current.value.options
  if (position < options.length) {
    event.preventDefault()
    toggleOption(options[position]!.label)
  } else if (position === options.length) {
    event.preventDefault()
    focusCustom()
  }
}

onMounted(() => {
  window.addEventListener('keydown', handleKeydown)
  rootRef.value?.focus({ preventScroll: true })
})
onBeforeUnmount(() => window.removeEventListener('keydown', handleKeydown))
</script>

<template>
  <section ref="rootRef" class="agent-question" role="group" aria-label="Agent 提问" tabindex="-1">
    <header class="agent-question-head">
      <div class="agent-question-heading">
        <span class="agent-question-kicker">{{ current.header || '需要你的确认' }}</span>
        <strong class="agent-question-title">{{ current.question }}</strong>
      </div>
      <div class="agent-question-controls">
        <button
          type="button"
          class="agent-question-icon"
          :aria-label="collapsed ? '展开问题' : '收起问题'"
          :aria-expanded="!collapsed"
          @click="collapsed = !collapsed"
        >
          <ChevronDown :size="14" :class="{ 'agent-question-chevron-up': collapsed }" />
        </button>
        <button
          type="button"
          class="agent-question-icon"
          aria-label="跳过提问"
          :disabled="submitting"
          @click="emit('skip')"
        >
          <X :size="14" />
        </button>
      </div>
    </header>

    <template v-if="!collapsed">
      <div
        class="agent-question-options"
        :role="current.multiSelect ? 'group' : 'radiogroup'"
        :aria-label="current.question"
      >
        <button
          v-for="(option, optionIndex) in current.options"
          :key="option.label"
          type="button"
          class="agent-question-option"
          :class="{ 'agent-question-option-selected': isSelected(option.label) }"
          :role="current.multiSelect ? 'checkbox' : 'radio'"
          :aria-checked="isSelected(option.label)"
          :disabled="submitting"
          @click="toggleOption(option.label)"
        >
          <span
            v-if="current.multiSelect"
            class="agent-question-box"
            :class="{ 'agent-question-box-checked': isSelected(option.label) }"
            aria-hidden="true"
          >
            <Check v-if="isSelected(option.label)" :size="11" />
          </span>
          <kbd v-else class="agent-question-key">{{ optionIndex + 1 }}</kbd>
          <strong class="agent-question-label">{{ option.label }}</strong>
          <span v-if="option.recommended" class="agent-question-tag">推荐</span>
          <span v-if="option.description" class="agent-question-desc">
            {{ option.description }}
          </span>
        </button>
        <label class="agent-question-option agent-question-custom">
          <span
            v-if="current.multiSelect"
            class="agent-question-box"
            :class="{ 'agent-question-box-checked': customs[current.id]!.trim() !== '' }"
            aria-hidden="true"
          >
            <Check v-if="customs[current.id]!.trim() !== ''" :size="11" />
          </span>
          <span v-else class="agent-question-key" aria-hidden="true">
            <SquarePen :size="11" />
          </span>
          <input
            ref="customInput"
            :key="current.id"
            class="agent-question-input"
            type="text"
            maxlength="2000"
            placeholder="输入你的答案"
            aria-label="输入你的答案"
            :disabled="submitting"
            :value="customs[current.id]"
            @input="onCustomInput(($event.target as HTMLInputElement).value)"
            @keydown.enter.prevent="advance"
          />
        </label>
      </div>

      <footer class="agent-question-footer">
        <div class="agent-question-pager" aria-label="题目导航">
          <template v-if="questions.length > 1">
            <button
              type="button"
              class="agent-question-icon"
              aria-label="切换到上一题"
              :disabled="index === 0"
              @click="go(-1)"
            >
              <ChevronLeft :size="14" />
            </button>
            <span class="agent-question-count">{{ index + 1 }} / {{ questions.length }}</span>
            <button
              type="button"
              class="agent-question-icon"
              aria-label="切换到下一题"
              :disabled="isLast || !canAdvance"
              @click="go(1)"
            >
              <ChevronRight :size="14" />
            </button>
          </template>
        </div>
        <div class="agent-question-actions">
          <NButton size="small" secondary :disabled="submitting" @click="emit('skip')">
            跳过
          </NButton>
          <NButton
            size="small"
            type="primary"
            :loading="submitting"
            :disabled="!canAdvance || (isLast && !canSubmit)"
            @click="advance"
          >
            {{ isLast ? '提交' : '下一题' }}
          </NButton>
        </div>
      </footer>
    </template>
  </section>
</template>

<style scoped>
.agent-question {
  padding: 12px 14px 10px;
  border: 1px solid var(--agent-border);
  border-radius: 20px;
  color: var(--agent-text);
  background: var(--agent-elevated);
  box-shadow: 0 10px 34px rgba(var(--app-primary-rgb), 0.1);
  outline: none;
}

.agent-question-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 10px;
}

.agent-question-heading {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 4px;
}

.agent-question-kicker {
  color: var(--agent-muted);
  font-size: 10px;
  font-weight: 600;
}

.agent-question-title {
  font-size: 13px;
  line-height: 1.4;
  overflow-wrap: anywhere;
}

.agent-question-controls,
.agent-question-pager,
.agent-question-actions {
  display: flex;
  align-items: center;
  gap: 6px;
}

.agent-question-icon {
  display: grid;
  width: 22px;
  height: 22px;
  place-items: center;
  padding: 0;
  border: 0;
  border-radius: var(--app-radius-control);
  color: var(--agent-muted);
  background: transparent;
  cursor: pointer;
}

.agent-question-icon:hover:not(:disabled) {
  color: var(--agent-text);
  background: var(--agent-hover);
}

.agent-question-icon:disabled {
  opacity: 0.35;
  cursor: default;
}

.agent-question-chevron-up {
  transform: rotate(180deg);
}

.agent-question-options {
  display: flex;
  flex-direction: column;
  gap: 2px;
  margin-top: 10px;
}

.agent-question-option {
  display: flex;
  align-items: center;
  gap: 9px;
  width: 100%;
  min-height: 34px;
  padding: 5px 9px;
  border: 1px solid transparent;
  border-radius: 10px;
  color: inherit;
  background: transparent;
  font: inherit;
  font-size: 12px;
  text-align: left;
  cursor: pointer;
}

.agent-question-option:hover:not(:disabled),
.agent-question-option-selected {
  background: var(--agent-hover);
}

.agent-question-option-selected {
  border-color: var(--app-primary-border);
}

.agent-question-key,
.agent-question-box {
  display: grid;
  width: 18px;
  height: 18px;
  flex: 0 0 auto;
  place-items: center;
  border-radius: 5px;
  color: var(--agent-muted);
  background: var(--agent-hover);
  font: inherit;
  font-size: 10px;
  font-weight: 600;
}

.agent-question-box {
  border: 1px solid var(--agent-border);
  background: transparent;
}

.agent-question-box-checked {
  border-color: var(--app-primary-border);
  color: #fff;
  background: rgb(var(--app-primary-rgb));
}

.agent-question-label {
  flex: 0 0 auto;
  font-weight: 600;
}

.agent-question-tag {
  flex: 0 0 auto;
  padding: 0 6px;
  border-radius: 6px;
  color: rgb(var(--app-primary-rgb));
  background: rgba(var(--app-primary-rgb), 0.12);
  font-size: 10px;
  line-height: 16px;
}

.agent-question-desc {
  min-width: 0;
  overflow: hidden;
  color: var(--agent-muted);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.agent-question-custom {
  cursor: text;
}

.agent-question-input {
  min-width: 0;
  flex: 1;
  padding: 0;
  border: 0;
  outline: none;
  color: var(--agent-text);
  background: transparent;
  font: inherit;
}

.agent-question-input::placeholder {
  color: var(--agent-muted);
}

.agent-question-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin-top: 10px;
}

.agent-question-count {
  min-width: 36px;
  text-align: center;
  color: var(--agent-muted);
  font-size: 11px;
}
</style>

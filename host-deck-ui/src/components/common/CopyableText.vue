<script setup lang="ts">
import { getUiApi } from '@/lib/ui'

const props = withDefaults(
  defineProps<{
    text: string
    displayText?: string
    title?: string
    successMessage?: string
    errorMessage?: string
  }>(),
  {
    displayText: undefined,
    title: undefined,
    successMessage: '已复制到剪贴板。',
    errorMessage: '复制失败。',
  },
)

async function copyText() {
  try {
    await navigator.clipboard.writeText(props.text)
    getUiApi().message.success(props.successMessage)
  } catch (error) {
    console.error('Failed to copy text', error)
    getUiApi().message.error(props.errorMessage)
  }
}
</script>

<template>
  <span class="copyable-text" :title="title ?? text">
    <button type="button" class="copyable-text__value" @click.stop="copyText">
      {{ displayText ?? text }}
    </button>
  </span>
</template>

<style scoped>
.copyable-text {
  display: inline-flex;
  max-width: 100%;
  min-width: 0;
  align-items: center;
  gap: 6px;
  vertical-align: middle;
}

.copyable-text__value {
  min-width: 0;
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
  font: inherit;
  overflow: hidden;
  padding: 0;
  text-align: left;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.copyable-text__value:hover {
  text-decoration: underline;
}
</style>

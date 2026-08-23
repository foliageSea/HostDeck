<script setup lang="ts">
import { useSettingsStore } from '@/stores/settings'

export type FileCompressFormat = 'tar.gz' | 'zip'

defineProps<{
  filename: string
  format: FileCompressFormat
  loading?: boolean
  show: boolean
  targetName: string
}>()

const emit = defineEmits<{
  confirm: []
  'update:format': [value: FileCompressFormat]
  'update:show': [value: boolean]
  'update:targetName': [value: string]
}>()

const settingsStore = useSettingsStore()
const formatOptions = [
  { label: 'tar.gz', value: 'tar.gz' },
  { label: 'zip', value: 'zip' },
]
</script>

<template>
  <NModal
    :show="show"
    preset="card"
    title="压缩"
    style="width: min(480px, calc(100vw - 24px))"
    @update:show="(value: boolean) => emit('update:show', value)"
  >
    <NSpace vertical>
      <div
        :class="
          settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.92)]'
        "
      >
        将 {{ filename }} 压缩到当前目录。
      </div>
      <NSelect
        :value="format"
        :options="formatOptions"
        @update:value="(value: FileCompressFormat) => emit('update:format', value)"
      />
      <NInput
        :value="targetName"
        placeholder="输入压缩文件名称"
        @update:value="(value: string) => emit('update:targetName', value)"
        @keyup.enter="emit('confirm')"
      />
      <NSpace justify="end">
        <NButton quaternary :disabled="loading" @click="emit('update:show', false)">取消</NButton>
        <NButton quaternary type="primary" :loading="loading" @click="emit('confirm')"
          >压缩</NButton
        >
      </NSpace>
    </NSpace>
  </NModal>
</template>

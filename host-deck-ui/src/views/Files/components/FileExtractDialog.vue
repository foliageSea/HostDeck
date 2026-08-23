<script setup lang="ts">
import { useSettingsStore } from '@/stores/settings'

defineProps<{
  filename: string
  loading: boolean
  show: boolean
  targetName: string
}>()

const emit = defineEmits<{
  confirm: []
  'update:show': [value: boolean]
  'update:targetName': [value: string]
}>()

const settingsStore = useSettingsStore()
</script>

<template>
  <NModal
    :show="show"
    preset="card"
    title="解压缩"
    style="width: min(480px, calc(100vw - 24px))"
    @update:show="(value: boolean) => emit('update:show', value)"
  >
    <NSpace vertical>
      <div
        :class="
          settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.92)]'
        "
      >
        将 {{ filename }} 解压到当前目录下的新目录。
      </div>
      <NInput
        :value="targetName"
        placeholder="输入解压目录名称"
        @update:value="(value: string) => emit('update:targetName', value)"
        @keyup.enter="emit('confirm')"
      />
      <NSpace justify="end">
        <NButton quaternary :disabled="loading" @click="emit('update:show', false)">取消</NButton>
        <NButton quaternary type="primary" :loading="loading" @click="emit('confirm')"
          >解压</NButton
        >
      </NSpace>
    </NSpace>
  </NModal>
</template>

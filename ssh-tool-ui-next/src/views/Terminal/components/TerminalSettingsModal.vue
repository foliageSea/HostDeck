<script setup lang="ts">
import { useSettingsStore } from '@/stores/settings'

defineProps<{
  show: boolean
}>()

const emit = defineEmits<{
  'update:show': [value: boolean]
}>()

const settingsStore = useSettingsStore()
</script>

<template>
  <NModal
    :show="show"
    preset="card"
    title="终端设置"
    style="width: min(380px, calc(100vw - 24px))"
    @update:show="(value: boolean) => emit('update:show', value)"
  >
    <NSpace vertical size="large">
      <div>
        <div class="mb-[10px] text-[13px] text-[rgba(148,163,184,0.92)]">字体大小</div>
        <NSlider
          :value="settingsStore.terminalFontSize"
          :min="8"
          :max="32"
          :tooltip="false"
          @update:value="(value: number) => settingsStore.setTerminalFontSize(value)"
        />
      </div>

      <div>
        <div class="mb-[10px] text-[13px] text-[rgba(148,163,184,0.92)]">字体名称</div>
        <NInput
          :value="settingsStore.terminalFontFamily"
          placeholder="例如 Consolas, monospace"
          @update:value="(value: string) => settingsStore.setTerminalFontFamily(value)"
        />
      </div>

      <NSpace justify="end">
        <NButton @click="settingsStore.resetTerminalSettings()">恢复默认</NButton>
        <NButton type="primary" @click="emit('update:show', false)">完成</NButton>
      </NSpace>
    </NSpace>
  </NModal>
</template>

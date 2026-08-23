<script setup lang="ts">
import type { FileItem } from '@/api/files'
import { useSettingsStore } from '@/stores/settings'
import { formatFileSize, formatModifyTime } from '../utils/fileFormatters'

defineProps<{
  selectedCount: number
  selectedFile: FileItem | null
}>()

const settingsStore = useSettingsStore()
</script>

<template>
  <NCard
    v-if="selectedFile"
    size="small"
    class="app-radius-surface details-panel rounded-[16px]"
    :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.56)]' : 'bg-[rgba(255,255,255,0.84)]'"
  >
    <div class="flex min-w-0 items-center gap-[12px] whitespace-nowrap">
      <span
        class="flex-none text-[12px]"
        :class="
          settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.92)]'
        "
        >当前选择</span
      >
      <span class="truncate-line">{{
        selectedCount > 1 ? `已选 ${selectedCount} 项` : selectedFile.filename
      }}</span>
      <span
        class="flex-none text-[12px]"
        :class="
          settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.92)]'
        "
        >{{ selectedFile.isDirectory ? '目录' : formatFileSize(selectedFile.size) }}</span
      >
      <span
        class="flex-none text-[12px]"
        :class="
          settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.92)]'
        "
        >{{ formatModifyTime(selectedFile.modifyTime) }}</span
      >
    </div>
  </NCard>
</template>

<style scoped>
.details-panel :deep(.n-card__content) {
  padding: 8px 12px;
}
</style>

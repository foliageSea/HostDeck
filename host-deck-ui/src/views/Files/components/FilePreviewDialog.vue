<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted } from 'vue'
import type { FileItem } from '@/api/files'
import { useSettingsStore } from '@/stores/settings'
import { resolve } from '@/utils/path'
import { formatFileSize, formatModifyTime } from '../utils/fileFormatters'
import FileMediaPreview from './FileMediaPreview.vue'

const props = defineProps<{
  connectionId?: string | null
  file: FileItem | null
  path: string
  show: boolean
}>()

const emit = defineEmits<{
  'update:show': [value: boolean]
}>()

const settingsStore = useSettingsStore()
const filePath = computed(() => (props.file ? resolve(props.path, props.file.filename) : ''))

function handleKeydown(event: KeyboardEvent) {
  if (!props.show || event.key !== ' ') return
  event.preventDefault()
  event.stopPropagation()
  emit('update:show', false)
}

onMounted(() => window.addEventListener('keydown', handleKeydown, { capture: true }))
onBeforeUnmount(() => window.removeEventListener('keydown', handleKeydown, { capture: true }))
</script>

<template>
  <NModal
    :show="show"
    preset="card"
    :title="file?.filename ?? '预览'"
    style="width: min(720px, calc(100vw - 24px))"
    @update:show="(value: boolean) => emit('update:show', value)"
  >
    <div v-if="file" class="flex flex-col gap-[14px]">
      <div
        class="flex min-h-[220px] items-center justify-center rounded-[14px] p-[12px]"
        :class="settingsStore.isDark ? 'bg-[rgba(2,6,23,0.5)]' : 'bg-[rgba(241,245,249,0.8)]'"
      >
        <FileMediaPreview
          :connection-id="connectionId"
          :current-path="path"
          :file="file"
          variant="preview"
        />
      </div>
      <div class="flex flex-wrap items-center gap-x-[14px] gap-y-[5px] text-[12px] opacity-70">
        <span>{{ file.isDirectory ? '目录' : formatFileSize(file.size) }}</span>
        <span>{{ formatModifyTime(file.modifyTime) }}</span>
        <span class="min-w-0 break-all">{{ filePath }}</span>
      </div>
    </div>
  </NModal>
</template>

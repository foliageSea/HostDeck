<template>
  <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4 p-4 overflow-auto h-full">
    <div v-for="file in files" :key="file.filename"
      @click="$emit('select', file.filename, $event.ctrlKey || $event.metaKey)"
      @dblclick="$emit('open', file)"
      @contextmenu.prevent="$emit('contextmenu', $event, file)"
      :class="['flex flex-col items-center p-4 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 cursor-pointer transition-colors border border-transparent', 
        selectedFiles.has(file.filename) ? 'bg-blue-50 dark:bg-blue-900/30 border-blue-200 dark:border-blue-800 ring-2 ring-blue-500/20' : '']">
      <div class="relative mb-3">
        <FolderIcon v-if="file.isDirectory" class="w-16 h-16 text-yellow-500" />
        <FileIcon v-else class="w-16 h-16 text-gray-400" />
        <div v-if="selectedFiles.has(file.filename)" class="absolute -top-2 -right-2 bg-blue-500 text-white rounded-full p-1">
          <CheckIcon class="w-3 h-3" />
        </div>
      </div>
      <span class="text-sm text-center text-gray-700 dark:text-gray-300 break-all line-clamp-2 w-full px-2" :title="file.filename">
        {{ file.filename }}
      </span>
      <span class="text-xs text-gray-400 mt-1">
        {{ file.isDirectory ? '-' : formatSize(file.size) }}
      </span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { FolderIcon, FileIcon, CheckIcon } from 'lucide-vue-next'
import type { FileItem } from '@/stores/file'

const props = defineProps<{
  files: FileItem[]
  selectedFiles: Set<string>
}>()

const emit = defineEmits(['select', 'open', 'contextmenu'])

const formatSize = (bytes: number) => {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}
</script>

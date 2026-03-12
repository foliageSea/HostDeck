<template>
  <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 xl:grid-cols-8 gap-4 p-4 overflow-auto h-full content-start bg-white dark:bg-[#1e1e1e]">
    <div v-for="file in files" :key="file.filename"
      @click="$emit('select', file.filename, $event.ctrlKey || $event.metaKey)"
      @dblclick="$emit('open', file)"
      @contextmenu.prevent="$emit('contextmenu', $event, file)"
      :class="['flex flex-col items-center p-2 rounded-md cursor-default transition-all border border-transparent group w-full aspect-[4/5]', 
        selectedFiles.has(file.filename) 
          ? 'bg-[#e4effd] dark:bg-[#004275] border-[#b0d4fc] dark:border-[#0078d4]' 
          : 'hover:bg-gray-100 dark:hover:bg-[#2d2d2d]']">
      
      <div class="flex-1 flex items-center justify-center w-full">
         <FolderIcon v-if="file.isDirectory" class="w-16 h-16 text-[#00aaff] fill-current drop-shadow-sm" />
         <FileIcon v-else class="w-14 h-14 text-gray-400 drop-shadow-sm" />
      </div>

      <div class="mt-2 w-full text-center">
        <span 
          :class="['text-[13px] leading-tight break-words line-clamp-2 px-1 rounded', 
            selectedFiles.has(file.filename) 
              ? 'bg-[#007AFF] text-white' 
              : 'text-gray-700 dark:text-gray-300']"
          :title="file.filename"
        >
          {{ file.filename }}
        </span>
      </div>
      
      <div class="text-[10px] text-gray-400 mt-1 h-4">
         {{ file.isDirectory ? '' : formatSize(file.size) }}
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { FolderIcon, FileIcon } from 'lucide-vue-next'
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

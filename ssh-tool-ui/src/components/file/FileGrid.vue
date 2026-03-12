<template>
  <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 xl:grid-cols-8 gap-4 p-4 overflow-auto h-full content-start bg-background">
    <div v-for="file in files" :key="file.filename"
      @click="$emit('select', file.filename, $event.ctrlKey || $event.metaKey)"
      @dblclick="$emit('open', file)"
      @contextmenu.prevent="$emit('contextmenu', $event, file)"
      :class="['flex flex-col items-center p-2 rounded-lg cursor-default transition-all border border-transparent group w-full aspect-[4/5]', 
        selectedFiles.has(file.filename) 
          ? 'bg-accent/50 border-primary/50 ring-1 ring-primary' 
          : 'hover:bg-accent/30']">
      
      <div class="flex-1 flex items-center justify-center w-full">
         <FolderIcon v-if="file.isDirectory" class="w-16 h-16 text-blue-500 fill-current drop-shadow-sm" />
         <FileIcon v-else class="w-14 h-14 text-muted-foreground drop-shadow-sm" />
      </div>

      <div class="mt-2 w-full text-center">
        <span 
          :class="['text-[13px] leading-tight break-words line-clamp-2 px-1 rounded', 
            selectedFiles.has(file.filename) 
              ? 'bg-primary text-primary-foreground' 
              : 'text-foreground']"
          :title="file.filename"
        >
          {{ file.filename }}
        </span>
      </div>
      
      <div class="text-[10px] text-muted-foreground mt-1 h-4">
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
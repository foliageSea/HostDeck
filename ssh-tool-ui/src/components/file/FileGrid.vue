<template>
  <div
    class="grid grid-cols-[repeat(auto-fill,minmax(120px,1fr))] gap-4 p-4 overflow-auto h-full content-start bg-background custom-scrollbar"
    :class="{ 'scrolling': isScrolling }" @scroll="handleScroll">
    <div v-for="file in files" :key="file.filename" :data-filename="file.filename"
      @click="$emit('select', file.filename, $event.ctrlKey || $event.metaKey)" @dblclick="$emit('open', file)"
      @contextmenu.prevent.stop="$emit('contextmenu', $event, file)" :class="['flex flex-col items-center p-2 rounded-lg cursor-default transition-all border border-transparent group w-full aspect-[4/5]',
        selectedFiles.has(file.filename)
          ? 'bg-accent/50 border-primary/50 ring-1 ring-primary'
          : 'hover:bg-accent/30']">

      <div class="flex-1 flex items-center justify-center w-full">
        <FolderIcon v-if="file.isDirectory" class="w-16 h-16 text-primary fill-current drop-shadow-sm" />
        <ImageIcon v-else-if="isImage(file.filename)" class="w-14 h-14 text-primary/75 drop-shadow-sm" />
        <FilmIcon v-else-if="isVideo(file.filename)" class="w-14 h-14 text-primary/60 drop-shadow-sm" />
        <FileIcon v-else class="w-14 h-14 text-muted-foreground drop-shadow-sm" />
      </div>

      <div class="mt-2 w-full text-center h-[36px] flex items-start justify-center">
        <span :class="['text-[13px] leading-tight break-words line-clamp-2 px-1 rounded max-w-full',
          selectedFiles.has(file.filename)
            ? 'bg-primary text-primary-foreground'
            : 'text-foreground']" :title="file.filename">
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
import { ref, onUnmounted } from 'vue'
import { FolderIcon, FileIcon, ImageIcon, FilmIcon } from 'lucide-vue-next'
import type { FileItem } from '@/stores/file'

const props = defineProps<{
  files: FileItem[]
  selectedFiles: Set<string>
}>()

const emit = defineEmits(['select', 'open', 'contextmenu'])

const isScrolling = ref(false)
let scrollTimeout: any

const handleScroll = () => {
  isScrolling.value = true
  clearTimeout(scrollTimeout)
  scrollTimeout = setTimeout(() => {
    isScrolling.value = false
  }, 1000)
}

onUnmounted(() => {
  clearTimeout(scrollTimeout)
})

const isImage = (filename: string) => {
  const ext = filename.split('.').pop()?.toLowerCase()
  return ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico'].includes(ext || '')
}

const isVideo = (filename: string) => {
  const ext = filename.split('.').pop()?.toLowerCase()
  return ['mp4', 'webm', 'ogg', 'mov', 'mkv', 'avi'].includes(ext || '')
}

const formatSize = (bytes: number) => {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}
</script>

<template>
  <div class="h-full overflow-auto bg-background custom-scrollbar" :class="{ 'scrolling': isScrolling }" @scroll="handleScroll">
    <Table>
      <TableHeader class="sticky top-0 z-10 bg-background shadow-sm">
        <TableRow>
          <TableHead class="w-8 text-center"></TableHead>
          <TableHead>名称</TableHead>
          <TableHead class="w-24">大小</TableHead>
          <TableHead class="w-40">修改时间</TableHead>
          <TableHead class="w-32">种类</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="file in files" :key="file.filename" 
          @click="$emit('select', file.filename, $event.ctrlKey || $event.metaKey)"
          @dblclick="$emit('open', file)"
          @contextmenu.prevent="$emit('contextmenu', $event, file)"
          :class="['cursor-default select-none group', 
            selectedFiles.has(file.filename) 
              ? 'bg-accent text-accent-foreground data-[state=selected]:bg-muted' 
              : 'hover:bg-muted/50'
          ]">
          <TableCell class="py-1 text-center">
            <div v-if="selectedFiles.has(file.filename)" class="w-1.5 h-1.5 rounded-full bg-primary mx-auto"></div>
          </TableCell>
          <TableCell class="py-1">
            <div class="flex items-center gap-2">
              <FolderIcon v-if="file.isDirectory" class="w-4 h-4 text-blue-500 fill-current" />
              <FileIcon v-else class="w-4 h-4 text-muted-foreground" />
              <span class="truncate font-medium">{{ file.filename }}</span>
            </div>
          </TableCell>
          <TableCell class="py-1 font-mono text-xs text-muted-foreground">
            {{ file.isDirectory ? '--' : formatSize(file.size) }}
          </TableCell>
          <TableCell class="py-1 text-xs text-muted-foreground">
            {{ formatDate(file.modifyTime) }}
          </TableCell>
          <TableCell class="py-1 text-xs text-muted-foreground">
            {{ getKind(file) }}
          </TableCell>
        </TableRow>
        <TableRow v-if="files.length === 0">
          <TableCell colspan="5" class="h-24 text-center text-muted-foreground">
            暂无文件
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
</template>

<script setup lang="ts">
import { ref, onUnmounted } from 'vue'
import { FolderIcon, FileIcon } from 'lucide-vue-next'
import type { FileItem } from '@/stores/file'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

const props = defineProps<{
  files: FileItem[]
  selectedFiles: Set<string>
}>()

const emit = defineEmits(['select', 'selectAll', 'open', 'contextmenu'])

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

const formatSize = (bytes: number) => {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

const formatDate = (isoString?: string) => {
  if (!isoString) return '-'
  const d = new Date(isoString)
  return d.toLocaleDateString() + ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

const getKind = (file: FileItem) => {
  if (file.isDirectory) return '文件夹'
  const ext = file.filename.split('.').pop()?.toUpperCase()
  return ext ? `${ext} 文件` : '文件'
}
</script>
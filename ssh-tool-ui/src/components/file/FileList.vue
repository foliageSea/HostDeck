<template>
  <div class="overflow-auto h-full bg-white dark:bg-[#1e1e1e]">
    <table class="w-full text-left text-[13px] text-gray-700 dark:text-gray-300 border-collapse">
      <thead class="bg-white dark:bg-[#2d2d2d] sticky top-0 z-10 text-gray-500 border-b border-gray-200 dark:border-black">
        <tr>
          <th class="px-4 py-1.5 w-8 text-center font-normal">
          </th>
          <th class="px-2 py-1.5 font-normal">名称</th>
          <th class="px-2 py-1.5 w-24 font-normal">大小</th>
          <th class="px-2 py-1.5 w-40 font-normal">修改时间</th>
          <th class="px-2 py-1.5 w-32 font-normal">种类</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-transparent">
        <tr v-for="(file, index) in files" :key="file.filename" 
          @click="$emit('select', file.filename, $event.ctrlKey || $event.metaKey)"
          @dblclick="$emit('open', file)"
          @contextmenu.prevent="$emit('contextmenu', $event, file)"
          :class="['cursor-default select-none group', 
            selectedFiles.has(file.filename) 
              ? 'bg-[#007AFF] text-white dark:text-white' 
              : index % 2 === 0 ? 'bg-white dark:bg-[#1e1e1e]' : 'bg-[#f5f5f5] dark:bg-[#252526]'
          ]">
          <td class="px-4 py-1 text-center">
            <div v-if="selectedFiles.has(file.filename)" class="w-1.5 h-1.5 rounded-full bg-white/50 mx-auto"></div>
          </td>
          <td class="px-2 py-1">
            <div class="flex items-center gap-2">
              <FolderIcon v-if="file.isDirectory" :class="['w-4 h-4', selectedFiles.has(file.filename) ? 'text-white' : 'text-[#00aaff] fill-current']" />
              <FileIcon v-else :class="['w-4 h-4', selectedFiles.has(file.filename) ? 'text-white' : 'text-gray-400']" />
              <span class="truncate font-medium">{{ file.filename }}</span>
            </div>
          </td>
          <td :class="['px-2 py-1 font-mono text-xs', selectedFiles.has(file.filename) ? 'text-white/80' : 'text-gray-500 dark:text-gray-400']">
            {{ file.isDirectory ? '--' : formatSize(file.size) }}
          </td>
          <td :class="['px-2 py-1 text-xs', selectedFiles.has(file.filename) ? 'text-white/80' : 'text-gray-500 dark:text-gray-400']">
            {{ formatDate(file.modifyTime) }}
          </td>
          <td :class="['px-2 py-1 text-xs', selectedFiles.has(file.filename) ? 'text-white/80' : 'text-gray-500 dark:text-gray-400']">
            {{ getKind(file) }}
          </td>
        </tr>
        <tr v-if="files.length === 0">
          <td colspan="5" class="px-4 py-12 text-center text-gray-500 dark:text-gray-400">
            暂无文件
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { FolderIcon, FileIcon } from 'lucide-vue-next'
import type { FileItem } from '@/stores/file'

const props = defineProps<{
  files: FileItem[]
  selectedFiles: Set<string>
}>()

const emit = defineEmits(['select', 'selectAll', 'open', 'contextmenu'])

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

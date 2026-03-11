<template>
  <div class="overflow-auto h-full">
    <table class="w-full text-left text-sm text-gray-700 dark:text-gray-300">
      <thead class="bg-gray-50 dark:bg-gray-800 sticky top-0 z-10 shadow-sm">
        <tr>
          <th class="px-4 py-3 w-10 text-center">
            <input type="checkbox" 
              :checked="allSelected" 
              @change="$emit('selectAll')"
              class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
            >
          </th>
          <th class="px-4 py-3 font-medium">名称</th>
          <th class="px-4 py-3 w-32 font-medium">大小</th>
          <th class="px-4 py-3 w-48 font-medium">修改时间</th>
          <th class="px-4 py-3 w-20 font-medium text-right">操作</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-200 dark:divide-gray-700 bg-white dark:bg-gray-900">
        <tr v-for="file in files" :key="file.filename" 
          @click="$emit('select', file.filename, $event.ctrlKey || $event.metaKey)"
          @dblclick="$emit('open', file)"
          @contextmenu.prevent="$emit('contextmenu', $event, file)"
          :class="['hover:bg-gray-50 dark:hover:bg-gray-800 cursor-pointer transition-colors', 
            selectedFiles.has(file.filename) ? 'bg-blue-50 dark:bg-blue-900/30' : '']">
          <td class="px-4 py-2 text-center" @click.stop>
            <input type="checkbox" 
              :checked="selectedFiles.has(file.filename)" 
              @change="$emit('select', file.filename, true)"
              class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
            >
          </td>
          <td class="px-4 py-2">
            <div class="flex items-center gap-3">
              <FolderIcon v-if="file.isDirectory" class="w-5 h-5 text-yellow-500 flex-shrink-0" />
              <FileIcon v-else class="w-5 h-5 text-gray-400 flex-shrink-0" />
              <span class="truncate">{{ file.filename }}</span>
            </div>
          </td>
          <td class="px-4 py-2 text-gray-500 dark:text-gray-400 font-mono text-xs">
            {{ file.isDirectory ? '-' : formatSize(file.size) }}
          </td>
          <td class="px-4 py-2 text-gray-500 dark:text-gray-400 text-xs">
            {{ formatDate(file.modifyTime) }}
          </td>
          <td class="px-4 py-2 text-right">
            <button @click.stop="$emit('contextmenu', $event, file)" class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700">
              <MoreVerticalIcon class="w-4 h-4" />
            </button>
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
import { FolderIcon, FileIcon, MoreVerticalIcon } from 'lucide-vue-next'
import type { FileItem } from '@/stores/file'

const props = defineProps<{
  files: FileItem[]
  selectedFiles: Set<string>
}>()

const emit = defineEmits(['select', 'selectAll', 'open', 'contextmenu'])

const allSelected = computed(() => {
  return props.files.length > 0 && props.selectedFiles.size === props.files.length
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
  return new Date(isoString).toLocaleString()
}
</script>

<template>
  <div class="flex items-center justify-between p-2 bg-gray-100 dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700">
    <div class="flex items-center gap-2 flex-1">
      <button @click="emit('navigateUp')" class="p-1 hover:bg-gray-200 dark:hover:bg-gray-700 rounded text-gray-600 dark:text-gray-300" title="上级目录">
        <ArrowUpIcon class="w-5 h-5" />
      </button>
      <input 
        v-model="path" 
        @keyup.enter="emit('navigate', path)"
        class="border border-gray-300 dark:border-gray-600 rounded px-2 py-1 w-full max-w-xl bg-white dark:bg-gray-900 text-gray-900 dark:text-gray-100" 
        placeholder="当前路径"
      />
      <button @click="emit('refresh')" class="p-1 hover:bg-gray-200 dark:hover:bg-gray-700 rounded text-gray-600 dark:text-gray-300" title="刷新">
        <RefreshCwIcon class="w-5 h-5" />
      </button>
    </div>
    <div class="flex items-center gap-2 ml-4">
      <button @click="emit('upload')" class="flex items-center gap-1 px-3 py-1 bg-blue-500 text-white rounded hover:bg-blue-600 text-sm">
        <UploadIcon class="w-4 h-4" /> 上传
      </button>
      <button @click="emit('mkdir')" class="flex items-center gap-1 px-3 py-1 bg-green-500 text-white rounded hover:bg-green-600 text-sm">
        <FolderPlusIcon class="w-4 h-4" /> 新建文件夹
      </button>
      <div class="border-l border-gray-300 dark:border-gray-600 mx-2 h-6"></div>
      <button @click="emit('toggleView', 'list')" :class="['p-1 rounded', viewMode === 'list' ? 'bg-gray-300 dark:bg-gray-600' : 'hover:bg-gray-200 dark:hover:bg-gray-700']" title="列表视图">
        <ListIcon class="w-5 h-5 text-gray-700 dark:text-gray-200" />
      </button>
      <button @click="emit('toggleView', 'grid')" :class="['p-1 rounded', viewMode === 'grid' ? 'bg-gray-300 dark:bg-gray-600' : 'hover:bg-gray-200 dark:hover:bg-gray-700']" title="图标视图">
        <GridIcon class="w-5 h-5 text-gray-700 dark:text-gray-200" />
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import { ArrowUpIcon, RefreshCwIcon, UploadIcon, FolderPlusIcon, ListIcon, GridIcon } from 'lucide-vue-next'

const props = defineProps<{
  currentPath: string
  viewMode: 'list' | 'grid'
}>()

const emit = defineEmits(['navigate', 'navigateUp', 'refresh', 'upload', 'mkdir', 'toggleView'])

const path = ref(props.currentPath)

watch(() => props.currentPath, (newPath) => {
  path.value = newPath
})
</script>

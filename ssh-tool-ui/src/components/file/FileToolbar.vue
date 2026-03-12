<template>
  <div class="flex items-center justify-between px-4 py-3 bg-[#f6f6f6] dark:bg-[#2d2d2d] border-b border-gray-200 dark:border-black select-none">
    <!-- Navigation & Path -->
    <div class="flex items-center gap-4 flex-1">
      <div class="flex items-center gap-1">
        <button 
          @click="emit('navigateUp')" 
          class="p-1.5 rounded-md text-gray-500 hover:bg-gray-200 dark:text-gray-400 dark:hover:bg-gray-600 transition-colors disabled:opacity-50" 
          title="上级目录"
        >
          <ChevronLeftIcon class="w-5 h-5" />
        </button>
        <button 
          class="p-1.5 rounded-md text-gray-500 hover:bg-gray-200 dark:text-gray-400 dark:hover:bg-gray-600 transition-colors disabled:opacity-50"
          disabled
        >
          <ChevronRightIcon class="w-5 h-5" />
        </button>
      </div>
      
      <div class="font-semibold text-gray-700 dark:text-gray-200 px-2 truncate max-w-md">
         {{ currentFolderName }}
      </div>
    </div>

    <!-- Actions -->
    <div class="flex items-center gap-2">
       <div class="flex items-center bg-gray-200 dark:bg-gray-700 rounded-md p-0.5">
        <button 
          @click="emit('toggleView', 'list')" 
          :class="['p-1.5 rounded-sm transition-all', viewMode === 'list' ? 'bg-white dark:bg-gray-600 shadow-sm text-gray-800 dark:text-gray-100' : 'text-gray-500 dark:text-gray-400 hover:text-gray-700']" 
          title="列表视图"
        >
          <ListIcon class="w-4 h-4" />
        </button>
        <button 
          @click="emit('toggleView', 'grid')" 
          :class="['p-1.5 rounded-sm transition-all', viewMode === 'grid' ? 'bg-white dark:bg-gray-600 shadow-sm text-gray-800 dark:text-gray-100' : 'text-gray-500 dark:text-gray-400 hover:text-gray-700']" 
          title="图标视图"
        >
          <LayoutGridIcon class="w-4 h-4" />
        </button>
      </div>

      <div class="w-px h-6 bg-gray-300 dark:bg-gray-600 mx-2"></div>

      <button @click="emit('refresh')" class="p-1.5 rounded-md text-gray-500 hover:bg-gray-200 dark:text-gray-400 dark:hover:bg-gray-600" title="刷新">
        <RotateCwIcon class="w-4 h-4" />
      </button>
      
      <div class="relative group">
        <button class="p-1.5 rounded-md text-gray-500 hover:bg-gray-200 dark:text-gray-400 dark:hover:bg-gray-600">
           <MoreHorizontalIcon class="w-4 h-4" />
        </button>
        <!-- Dropdown for extra actions -->
        <div class="absolute right-0 top-full mt-1 w-40 bg-white dark:bg-gray-800 rounded-lg shadow-xl border border-gray-200 dark:border-gray-700 hidden group-hover:block z-20 py-1">
           <button @click="emit('upload')" class="w-full text-left px-4 py-2 text-sm text-gray-700 dark:text-gray-200 hover:bg-blue-500 hover:text-white">
             上传文件
           </button>
           <button @click="emit('mkdir')" class="w-full text-left px-4 py-2 text-sm text-gray-700 dark:text-gray-200 hover:bg-blue-500 hover:text-white">
             新建文件夹
           </button>
        </div>
      </div>
      
      <div class="ml-2 relative">
         <SearchIcon class="w-4 h-4 absolute left-2.5 top-1/2 -translate-y-1/2 text-gray-400" />
         <input 
            v-model="path"
            @keyup.enter="emit('navigate', path)"
            class="pl-9 pr-3 py-1 text-sm bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-md w-48 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-all"
            placeholder="搜索"
          />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import { 
  ChevronLeftIcon, ChevronRightIcon, RotateCwIcon, 
  ListIcon, LayoutGridIcon, SearchIcon, MoreHorizontalIcon 
} from 'lucide-vue-next'

const props = defineProps<{
  currentPath: string
  viewMode: 'list' | 'grid'
}>()

const emit = defineEmits(['navigate', 'navigateUp', 'refresh', 'upload', 'mkdir', 'toggleView'])

const path = ref(props.currentPath)

watch(() => props.currentPath, (newPath) => {
  path.value = newPath
})

const currentFolderName = computed(() => {
  const parts = props.currentPath.split('/').filter(Boolean)
  return parts.length > 0 ? parts[parts.length - 1] : '根目录'
})
</script>

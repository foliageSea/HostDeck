<template>
  <div class="flex items-center justify-between px-4 py-3 bg-background border-b select-none">
    <!-- Navigation & Path -->
    <div class="flex items-center gap-4 flex-1">
      <div class="flex items-center gap-1">
        <Button
          variant="ghost"
          size="icon"
          @click="$emit('navigateUp')"
          title="上级目录"
          class="h-8 w-8"
        >
          <ChevronLeftIcon class="w-5 h-5" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          disabled
          class="h-8 w-8"
        >
          <ChevronRightIcon class="w-5 h-5" />
        </Button>
      </div>
      
      <div class="font-semibold text-foreground px-2 truncate max-w-md">
         {{ currentFolderName }}
      </div>
    </div>

    <!-- Actions -->
    <div class="flex items-center gap-2">
       <div class="flex items-center bg-muted rounded-md p-1">
        <Button
          variant="ghost"
          size="icon"
          @click="$emit('toggleView', 'list')"
          :class="['h-7 w-7 rounded-sm', viewMode === 'list' ? 'bg-background shadow-sm' : 'hover:bg-transparent']"
          title="列表视图"
        >
          <ListIcon class="w-4 h-4" />
        </Button>
        <Button
          variant="ghost"
          size="icon"
          @click="$emit('toggleView', 'grid')"
          :class="['h-7 w-7 rounded-sm', viewMode === 'grid' ? 'bg-background shadow-sm' : 'hover:bg-transparent']"
          title="图标视图"
        >
          <LayoutGridIcon class="w-4 h-4" />
        </Button>
      </div>

      <div class="w-px h-6 bg-border mx-2"></div>

      <Button variant="ghost" size="icon" @click="$emit('refresh')" title="刷新" class="h-8 w-8">
        <RotateCwIcon class="w-4 h-4" />
      </Button>
      
      <DropdownMenu>
        <DropdownMenuTrigger as-child>
          <Button variant="ghost" size="icon" class="h-8 w-8">
            <MoreHorizontalIcon class="w-4 h-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
           <DropdownMenuItem @click="$emit('upload')">
             上传文件
           </DropdownMenuItem>
           <DropdownMenuItem @click="$emit('mkdir')">
             新建文件夹
           </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      
      <div class="ml-2 relative w-64">
         <SearchIcon class="w-4 h-4 absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
         <Input 
            v-model="path"
            @keyup.enter="$emit('navigate', path)"
            class="pl-9 h-9"
            placeholder="搜索 / 路径"
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
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'

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
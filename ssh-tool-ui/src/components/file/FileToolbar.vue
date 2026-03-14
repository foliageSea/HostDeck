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

      <Button variant="ghost" size="icon" class="h-8 w-8" title="上传文件" @click="triggerUpload('file')">
        <FileUpIcon class="w-4 h-4" />
      </Button>
      <!-- <Button variant="ghost" size="icon" class="h-8 w-8" title="上传文件夹" @click="triggerUpload('folder')">
        <FolderUpIcon class="w-4 h-4" />
      </Button> -->

      <input type="file" ref="fileInput" multiple class="hidden" @change="handleFileChange" />
      <input type="file" ref="folderInput" webkitdirectory class="hidden" @change="handleFileChange" />

      <Button variant="ghost" size="icon" @click="$emit('refresh')" title="刷新" class="h-8 w-8">
        <RotateCwIcon class="w-4 h-4" />
      </Button>

      <DropdownMenu>
        <DropdownMenuTrigger as-child>
          <Button variant="ghost" size="icon" class="h-8 w-8">
            <MoreHorizontalIcon class="w-4 h-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" class="z-[99999]">
           <DropdownMenuItem @click="$emit('mkdir')">
             新建文件夹
           </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      
      <div class="ml-2 relative w-64 flex items-center gap-1">
         <DropdownMenu>
            <DropdownMenuTrigger as-child>
              <Button variant="ghost" size="icon" class="h-9 w-9 shrink-0" title="收藏夹">
                <BookmarkIcon class="w-4 h-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" class="w-64 z-[99999]">
              <DropdownMenuLabel>收藏夹</DropdownMenuLabel>
              <DropdownMenuSeparator />
              <div v-if="fileStore.favorites.length === 0" class="px-2 py-1.5 text-sm text-muted-foreground text-center">
                暂无收藏
              </div>
              <DropdownMenuItem 
                v-for="fav in fileStore.favorites" 
                :key="fav" 
                @click="$emit('navigate', fav)"
                class="cursor-pointer truncate"
                :title="fav"
              >
                <span class="truncate">{{ fav }}</span>
              </DropdownMenuItem>
            </DropdownMenuContent>
         </DropdownMenu>

         <div class="relative flex-1">
            <Input 
              v-model="path"
              @keyup.enter="$emit('navigate', path)"
              class="h-9 pr-8" 
              placeholder="搜索 / 路径"
            />
            <Button
              variant="ghost"
              size="icon"
              class="absolute right-0 top-0 h-9 w-9 hover:bg-transparent"
              @click="fileStore.toggleFavorite(currentPath)"
              :title="fileStore.isFavorite(currentPath) ? '取消收藏' : '收藏当前目录'"
            >
              <StarIcon 
                class="w-4 h-4 transition-colors" 
                :class="fileStore.isFavorite(currentPath) ? 'fill-yellow-400 text-yellow-400' : 'text-muted-foreground'" 
              />
            </Button>
         </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import { 
  ChevronLeftIcon, ChevronRightIcon, RotateCwIcon, 
  ListIcon, LayoutGridIcon, SearchIcon, MoreHorizontalIcon,
  FileUpIcon, FolderUpIcon, StarIcon, BookmarkIcon
} from 'lucide-vue-next'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSeparator,
  DropdownMenuLabel
} from '@/components/ui/dropdown-menu'
import { useFileStore } from '@/stores/file'

const fileStore = useFileStore()

const props = defineProps<{
  currentPath: string
  viewMode: 'list' | 'grid'
}>()

const emit = defineEmits(['navigate', 'navigateUp', 'refresh', 'upload', 'upload-folder', 'upload-files', 'mkdir', 'toggleView'])

const fileInput = ref<HTMLInputElement>()
const folderInput = ref<HTMLInputElement>()

const triggerUpload = (mode: 'file' | 'folder') => {
  if (mode === 'folder') {
    folderInput.value?.click()
  } else {
    fileInput.value?.click()
  }
}

const handleFileChange = (e: Event) => {
  const input = e.target as HTMLInputElement
  if (input.files && input.files.length > 0) {
    emit('upload-files', input.files)
    input.value = ''
  }
}

const path = ref(props.currentPath)

watch(() => props.currentPath, (newPath) => {
  path.value = newPath
})

const currentFolderName = computed(() => {
  const parts = props.currentPath.split('/').filter(Boolean)
  return parts.length > 0 ? parts[parts.length - 1] : '根目录'
})
</script>
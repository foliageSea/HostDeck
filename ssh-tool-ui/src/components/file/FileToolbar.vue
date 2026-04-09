<template>
  <div class="flex items-center justify-between px-4 py-3 bg-background border-b select-none">
    <!-- Navigation & Path -->
    <div class="flex items-center gap-4 flex-1 min-w-0">
      <div class="flex items-center gap-1">
        <Button variant="ghost" size="icon" @click="$emit('navigateBack')" title="后退" class="h-8 w-8"
          :disabled="!canNavigateBack">
          <ChevronLeftIcon class="w-5 h-5" />
        </Button>
        <Button variant="ghost" size="icon" @click="$emit('navigateForward')" title="前进" class="h-8 w-8"
          :disabled="!canNavigateForward">
          <ChevronRightIcon class="w-5 h-5" />
        </Button>
        <Button variant="ghost" size="icon" @click="$emit('navigateUp')" title="上级目录" class="h-8 w-8">
          <ArrowUpIcon class="w-4 h-4" />
        </Button>
      </div>

      <div class="hidden lg:flex items-center gap-1 min-w-0 overflow-hidden flex-nowrap">
        <Button variant="ghost" class="h-8 px-2 shrink-0" @click="$emit('navigate', '/')">
          根目录
        </Button>
        <template v-for="crumb in breadcrumbs" :key="crumb.path">
          <span class="text-muted-foreground shrink-0">/</span>
          <Button variant="ghost" class="h-8 px-2 max-w-[160px] min-w-0" @click="$emit('navigate', crumb.path)"
            :title="crumb.path">
            <span class="truncate block">{{ crumb.label }}</span>
          </Button>
        </template>

        <DropdownMenu>
          <DropdownMenuTrigger as-child>
            <Button variant="ghost" size="icon" class="h-8 w-8 shrink-0" title="快速跳转">
              <ChevronDownIcon class="w-4 h-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" class="w-64 z-[99999]">
            <DropdownMenuLabel>面包屑快速跳转</DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              v-for="item in breadcrumbJumpItems"
              :key="item.path"
              @click="$emit('navigate', item.path)"
              class="cursor-pointer"
            >
              <span class="truncate" :title="item.path">{{ item.path }}</span>
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <div class="lg:hidden font-semibold text-foreground px-2 truncate max-w-md">
        {{ currentFolderName }}
      </div>
    </div>

    <!-- Actions -->
      <div class="flex items-center gap-2 min-w-0">

      <div class="relative w-56 hidden md:block">
        <Input :model-value="searchQuery" @update:model-value="value => $emit('updateSearchQuery', value)" class="h-9"
          placeholder="搜索当前目录" />
      </div>

      <div class="flex items-center bg-muted rounded-md p-1">
        <Button variant="ghost" size="icon" @click="$emit('toggleView', 'list')"
          :class="['h-7 w-7 rounded-sm', viewMode === 'list' ? 'bg-background shadow-sm' : 'hover:bg-transparent']"
          title="列表视图">
          <ListIcon class="w-4 h-4" />
        </Button>
        <Button variant="ghost" size="icon" @click="$emit('toggleView', 'grid')"
          :class="['h-7 w-7 rounded-sm', viewMode === 'grid' ? 'bg-background shadow-sm' : 'hover:bg-transparent']"
          title="图标视图">
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

      <Button variant="ghost" size="icon" @click="$emit('open-terminal')" title="在终端中打开" class="h-8 w-8">
        <TerminalIcon class="w-4 h-4" />
      </Button>


      <div class="ml-2 flex items-center gap-1 shrink-0">
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
            <DropdownMenuItem v-for="fav in fileStore.favorites" :key="fav" @click="$emit('navigate', fav)"
              class="cursor-pointer truncate" :title="fav">
              <span class="truncate">{{ fav }}</span>
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>


        <DropdownMenu>
          <DropdownMenuTrigger as-child>
            <Button variant="ghost" size="icon" class="h-8 w-8">
              <ArrowUpDownIcon class="w-4 h-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" class="z-[99999]">
            <DropdownMenuLabel>排序与筛选</DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuSub>
              <DropdownMenuSubTrigger>排序字段</DropdownMenuSubTrigger>
              <DropdownMenuSubContent>
                <DropdownMenuRadioGroup :model-value="sortBy" @update:model-value="value => $emit('updateSortBy', value)">
                  <DropdownMenuRadioItem value="name">名称</DropdownMenuRadioItem>
                  <DropdownMenuRadioItem value="size">大小</DropdownMenuRadioItem>
                  <DropdownMenuRadioItem value="modifyTime">修改时间</DropdownMenuRadioItem>
                  <DropdownMenuRadioItem value="type">类型</DropdownMenuRadioItem>
                </DropdownMenuRadioGroup>
              </DropdownMenuSubContent>
            </DropdownMenuSub>
            <DropdownMenuItem @click="$emit('toggleSortOrder')">
              {{ sortOrder === 'asc' ? '切换为降序' : '切换为升序' }}
            </DropdownMenuItem>
            <DropdownMenuSub>
              <DropdownMenuSubTrigger>筛选</DropdownMenuSubTrigger>
              <DropdownMenuSubContent>
                <DropdownMenuItem @click="$emit('updateFilterType', 'all')">全部</DropdownMenuItem>
                <DropdownMenuItem @click="$emit('updateFilterType', 'directory')">仅目录</DropdownMenuItem>
                <DropdownMenuItem @click="$emit('updateFilterType', 'file')">仅文件</DropdownMenuItem>
              </DropdownMenuSubContent>
            </DropdownMenuSub>
          </DropdownMenuContent>
        </DropdownMenu>

        <DropdownMenu>
          <DropdownMenuTrigger as-child>
            <Button variant="ghost" size="icon" class="h-8 w-8">
              <MoreHorizontalIcon class="w-4 h-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" class="z-[99999]">
            <DropdownMenuItem @click="$emit('createFile')">
              新建文件
            </DropdownMenuItem>
            <DropdownMenuItem @click="$emit('mkdir')">
              新建文件夹
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>


        <Button variant="ghost" size="icon" class="h-9 w-9 shrink-0"
          @click="fileStore.toggleFavorite(currentPath)"
          :title="fileStore.isFavorite(currentPath) ? '取消收藏' : '收藏当前目录'">
          <StarIcon class="w-4 h-4 transition-colors"
            :class="fileStore.isFavorite(currentPath) ? 'fill-yellow-400 text-yellow-400' : 'text-muted-foreground'" />
        </Button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import {
  ChevronLeftIcon, ChevronRightIcon, RotateCwIcon, ArrowUpIcon, ChevronDownIcon,
  ListIcon, LayoutGridIcon, MoreHorizontalIcon, ArrowUpDownIcon,
  FileUpIcon, StarIcon, BookmarkIcon, Terminal as TerminalIcon
} from 'lucide-vue-next'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSeparator,
  DropdownMenuLabel,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem
} from '@/components/ui/dropdown-menu'
import { useFileStore } from '@/stores/file'
import type { FilterType, SortBy, SortOrder } from '@/stores/file'

const fileStore = useFileStore()

const props = defineProps<{
  currentPath: string
  viewMode: 'list' | 'grid'
  canNavigateBack: boolean
  canNavigateForward: boolean
  searchQuery: string
  sortBy: SortBy
  sortOrder: SortOrder
  filterType: FilterType
}>()

const emit = defineEmits(['navigate', 'navigateUp', 'navigateBack', 'navigateForward', 'refresh', 'upload', 'upload-folder', 'upload-files', 'mkdir', 'createFile', 'toggleView', 'open-terminal', 'updateSearchQuery', 'updateSortBy', 'toggleSortOrder', 'updateFilterType'])

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

const currentFolderName = computed(() => {
  const parts = props.currentPath.split('/').filter(Boolean)
  return parts.length > 0 ? parts[parts.length - 1] : '根目录'
})

const breadcrumbs = computed(() => {
  const parts = props.currentPath.split('/').filter(Boolean)
  let current = ''

  return parts.map((part) => {
    current += `/${part}`
    return {
      label: part,
      path: current
    }
  })
})

const breadcrumbJumpItems = computed(() => {
  const items = [{ path: '/' }]

  for (const crumb of breadcrumbs.value) {
    items.push({ path: crumb.path })
  }

  return items.reverse()
})
</script>

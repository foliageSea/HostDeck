<script setup lang="ts">
import {
  ArrowLeft,
  ArrowRight,
  ArrowUp,
  Grid,
  Help,
  List,
  Renew,
  SortAscending,
  SortDescending,
} from '@vicons/carbon'
import type { FileSortKey } from '@/stores/file'
import { useSettingsStore } from '@/stores/settings'

defineProps<{
  canGoBack: boolean
  canGoForward: boolean
  search: string
  sortDirection: 'asc' | 'desc'
  sortKey: FileSortKey
  viewMode: 'list' | 'grid'
}>()

const emit = defineEmits<{
  navigateBack: []
  navigateForward: []
  navigateUp: []
  refresh: []
  toggleSortDirection: []
  'update:search': [value: string]
  'update:sortKey': [value: FileSortKey]
  'update:viewMode': [value: 'list' | 'grid']
}>()

const settingsStore = useSettingsStore()
const sortOptions: { label: string; value: FileSortKey }[] = [
  { label: '名称', value: 'name' },
  { label: '大小', value: 'size' },
  { label: '修改时间', value: 'modifyTime' },
]
</script>

<template>
  <div class="flex flex-wrap items-center justify-between gap-[12px]">
    <NSpace align="center" wrap>
      <NTooltip>
        <template #trigger>
          <NButton quaternary :disabled="!canGoBack" @click="emit('navigateBack')">
            <template #icon
              ><NIcon><ArrowLeft /></NIcon
            ></template>
          </NButton>
        </template>
        返回
      </NTooltip>
      <NTooltip>
        <template #trigger>
          <NButton quaternary :disabled="!canGoForward" @click="emit('navigateForward')">
            <template #icon
              ><NIcon><ArrowRight /></NIcon
            ></template>
          </NButton>
        </template>
        前进
      </NTooltip>
      <NTooltip>
        <template #trigger>
          <NButton quaternary @click="emit('navigateUp')">
            <template #icon
              ><NIcon><ArrowUp /></NIcon
            ></template>
          </NButton>
        </template>
        上级目录
      </NTooltip>
      <NTooltip>
        <template #trigger>
          <NButton quaternary @click="emit('refresh')">
            <template #icon
              ><NIcon><Renew /></NIcon
            ></template>
          </NButton>
        </template>
        刷新
      </NTooltip>
    </NSpace>

    <div class="flex items-center gap-[8px]">
      <NInput
        :value="search"
        placeholder="搜索当前目录"
        clearable
        class="w-[min(240px,60vw)]"
        @update:value="(value: string) => emit('update:search', value)"
      />
      <NSelect
        :value="sortKey"
        :options="sortOptions"
        class="w-[116px] flex-none"
        @update:value="(value: FileSortKey) => emit('update:sortKey', value)"
      />
      <NTooltip>
        <template #trigger>
          <NButton quaternary @click="emit('toggleSortDirection')">
            <template #icon>
              <NIcon>
                <SortAscending v-if="sortDirection === 'asc'" />
                <SortDescending v-else />
              </NIcon>
            </template>
          </NButton>
        </template>
        {{ sortDirection === 'asc' ? '升序' : '降序' }}
      </NTooltip>
      <div class="flex items-center gap-[8px]">
        <NTooltip>
          <template #trigger>
            <NButton
              quaternary
              :type="viewMode === 'list' ? 'primary' : 'default'"
              @click="emit('update:viewMode', 'list')"
            >
              <template #icon
                ><NIcon><List /></NIcon
              ></template>
            </NButton>
          </template>
          列表视图
        </NTooltip>
        <NTooltip>
          <template #trigger>
            <NButton
              quaternary
              :type="viewMode === 'grid' ? 'primary' : 'default'"
              @click="emit('update:viewMode', 'grid')"
            >
              <template #icon
                ><NIcon><Grid /></NIcon
              ></template>
            </NButton>
          </template>
          网格视图
        </NTooltip>
        <NPopover trigger="hover" placement="bottom-end">
          <template #trigger>
            <NButton quaternary
              ><template #icon
                ><NIcon><Help /></NIcon></template
            ></NButton>
          </template>
          <div
            class="flex flex-col gap-[6px] text-[12px]"
            :class="
              settingsStore.isDark ? 'text-[rgba(226,232,240,0.96)]' : 'text-[rgba(51,65,85,0.96)]'
            "
          >
            <div>Ctrl/Cmd + Click：多选</div>
            <div>Shift + Click：范围选择</div>
            <div>Ctrl/Cmd + A：全选</div>
            <div>Ctrl/Cmd + C：复制</div>
            <div>Ctrl/Cmd + X：移动</div>
            <div>Ctrl/Cmd + V：粘贴</div>
            <div>Ctrl/Cmd + U：上传</div>
            <div>Ctrl/Cmd + D：下载</div>
            <div>Delete：删除</div>
            <div>F2：重命名</div>
            <div>Enter：打开选中项</div>
          </div>
        </NPopover>
      </div>
    </div>
  </div>
</template>

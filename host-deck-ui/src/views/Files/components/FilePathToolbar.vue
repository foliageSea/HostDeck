<script setup lang="ts">
import {
  ArrowRight,
  Close,
  LocationStar,
  Pin,
  PinFilled,
  Star,
  StarFilled,
  Terminal,
} from '@vicons/carbon'
import { useSettingsStore } from '@/stores/settings'
import { formatFavoritePath } from '../utils/fileFormatters'

export interface FileBreadcrumb {
  label: string
  path: string
}

defineProps<{
  breadcrumbs: FileBreadcrumb[]
  currentPathInput: string
  editingPath: boolean
  favoritePaths: string[]
  isCurrentPathFavorite: boolean
  isCurrentPathPinned: boolean
}>()

const emit = defineEmits<{
  navigate: [path: string]
  openTerminal: []
  removeFavorite: [path: string]
  startEditing: []
  stopEditing: []
  submitPath: []
  toggleFavorite: []
  togglePin: []
  'update:currentPathInput': [value: string]
}>()

const settingsStore = useSettingsStore()
</script>

<template>
  <div class="flex flex-wrap items-center justify-between gap-[12px]">
    <div
      v-if="!editingPath"
      class="min-w-[240px] flex-1 overflow-x-auto pb-[2px] app-scrollbar app-scrollbar-compact"
      :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'"
    >
      <NBreadcrumb>
        <NBreadcrumbItem v-for="item in breadcrumbs" :key="item.path">
          <button
            type="button"
            class="btn-reset hover:text-[rgba(96,165,250,0.95)]"
            @click="emit('navigate', item.path)"
          >
            {{ item.label }}
          </button>
        </NBreadcrumbItem>
      </NBreadcrumb>
    </div>
    <div v-else class="path-editor min-w-[240px] flex-1">
      <NInput
        :value="currentPathInput"
        placeholder="输入远程路径快速跳转"
        @update:value="(value: string) => emit('update:currentPathInput', value)"
        @keyup.enter="emit('submitPath')"
        @keyup.esc="emit('stopEditing')"
        @blur="emit('stopEditing')"
      />
    </div>

    <div class="flex flex-wrap items-center justify-end gap-[12px]">
      <NButton
        v-if="editingPath"
        quaternary
        size="small"
        type="primary"
        @mousedown.prevent
        @click="emit('submitPath')"
        >跳转</NButton
      >
      <NTooltip v-else>
        <template #trigger>
          <NButton quaternary size="small" @click="emit('startEditing')">
            <template #icon
              ><NIcon><ArrowRight /></NIcon
            ></template>
          </NButton>
        </template>
        输入路径跳转
      </NTooltip>
      <NTooltip>
        <template #trigger>
          <NButton
            quaternary
            size="small"
            :type="isCurrentPathFavorite ? 'warning' : 'default'"
            @click="emit('toggleFavorite')"
          >
            <template #icon>
              <NIcon><component :is="isCurrentPathFavorite ? StarFilled : Star" /></NIcon>
            </template>
          </NButton>
        </template>
        {{ isCurrentPathFavorite ? '取消收藏当前目录' : '收藏当前目录' }}
      </NTooltip>
      <NTooltip>
        <template #trigger>
          <NButton
            quaternary
            size="small"
            :type="isCurrentPathPinned ? 'primary' : 'default'"
            @click="emit('togglePin')"
          >
            <template #icon>
              <NIcon><component :is="isCurrentPathPinned ? PinFilled : Pin" /></NIcon>
            </template>
          </NButton>
        </template>
        {{ isCurrentPathPinned ? '从桌面移除当前目录' : '将当前目录钉到桌面' }}
      </NTooltip>
      <NPopover v-if="favoritePaths.length > 0" trigger="click" placement="bottom-end">
        <template #trigger>
          <NButton quaternary size="small" class="md:hidden">
            <template #icon
              ><NIcon><LocationStar /></NIcon
            ></template>
          </NButton>
        </template>
        <div class="w-[min(360px,72vw)]">
          <div
            class="mb-[10px] text-[13px] font-600"
            :class="
              settingsStore.isDark ? 'text-[rgba(226,232,240,0.96)]' : 'text-[rgba(51,65,85,0.96)]'
            "
          >
            收藏目录
          </div>
          <NScrollbar
            class="app-scrollbar app-scrollbar-compact"
            :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'"
            style="max-height: 260px"
          >
            <div class="flex flex-col gap-[6px] pr-[10px]">
              <div
                v-for="path in favoritePaths"
                :key="path"
                class="app-radius-control flex min-w-0 items-center gap-[8px] rounded-[10px] py-[6px] pl-[10px] pr-[6px]"
                :class="
                  settingsStore.isDark ? 'bg-[rgba(15,23,42,0.5)]' : 'bg-[rgba(241,245,249,0.92)]'
                "
              >
                <button
                  type="button"
                  class="btn-reset truncate-line flex-1 text-left hover:text-[rgba(96,165,250,0.95)]"
                  :title="path"
                  @click="emit('navigate', path)"
                >
                  {{ formatFavoritePath(path) }}
                </button>
                <NButton quaternary size="tiny" @click.stop="emit('removeFavorite', path)">
                  <template #icon
                    ><NIcon><Close /></NIcon
                  ></template>
                </NButton>
              </div>
            </div>
          </NScrollbar>
        </div>
      </NPopover>
      <NTooltip>
        <template #trigger>
          <NButton quaternary size="small" @click="emit('openTerminal')">
            <template #icon
              ><NIcon><Terminal /></NIcon
            ></template>
          </NButton>
        </template>
        在当前目录打开终端
      </NTooltip>
    </div>
  </div>
</template>

<style scoped>
.path-editor :deep(.n-input) {
  width: 100%;
}
</style>

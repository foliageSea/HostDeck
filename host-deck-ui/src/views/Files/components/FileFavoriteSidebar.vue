<script setup lang="ts">
import { computed } from 'vue'
import { ChevronLeft, ChevronRight, Close } from '@vicons/carbon'
import { useSettingsStore } from '@/stores/settings'
import { basename } from '@/utils/path'

const props = defineProps<{
  currentPath: string
  favoritePaths: string[]
  isCurrentPathFavorite: boolean
  visible: boolean
}>()

const emit = defineEmits<{
  navigate: [path: string]
  remove: [path: string]
  toggleCurrentFavorite: []
  toggleVisibility: []
}>()

const settingsStore = useSettingsStore()

const handleTooltip = computed(() => (props.visible ? '收起收藏侧栏' : '展开收藏侧栏'))

function formatFavoritePath(path: string) {
  return basename(path) || '根目录'
}
</script>

<template>
  <div
    class="favorite-sidebar-shell relative hidden min-h-0 shrink-0 transition-[width] duration-[220ms] ease-in-out md:flex"
    :class="visible ? 'w-[252px]' : 'w-[30px]'"
  >
    <aside
      class="absolute inset-y-0 left-0 flex w-[252px] min-w-[220px] flex-col overflow-hidden rounded-[18px] border transition-[opacity,transform] duration-[220ms] ease-in-out"
      :class="[
        settingsStore.isDark
          ? 'border-[rgba(148,163,184,0.14)] bg-[rgba(15,23,42,0.72)]'
          : 'border-[rgba(148,163,184,0.22)] bg-[rgba(248,250,252,0.84)]',
        visible ? 'translate-x-0 opacity-100' : 'pointer-events-none -translate-x-[18px] opacity-0',
      ]"
    >
      <div class="flex items-center justify-between gap-[10px] px-[14px] pb-[10px] pt-[14px]">
        <div class="min-w-0">
          <div
            class="text-[13px] font-600"
            :class="
              settingsStore.isDark ? 'text-[rgba(226,232,240,0.96)]' : 'text-[rgba(51,65,85,0.96)]'
            "
          >
            收藏目录
          </div>
          <div
            class="mt-[2px] text-[12px]"
            :class="
              settingsStore.isDark
                ? 'text-[rgba(148,163,184,0.9)]'
                : 'text-[rgba(100,116,139,0.92)]'
            "
          >
            {{ favoritePaths.length }} 项
          </div>
        </div>
      </div>

      <div class="min-h-0 flex-1 px-[10px] pb-[12px]">
        <NEmpty
          v-if="favoritePaths.length === 0"
          size="small"
          description="暂无收藏"
          class="flex h-full items-center justify-center"
        />
        <NScrollbar
          v-else
          class="h-full app-scrollbar app-scrollbar-compact"
          :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'"
        >
          <div class="flex flex-col gap-[8px] pr-[10px]">
            <div
              v-for="path in favoritePaths"
              :key="path"
              class="group grid w-full cursor-pointer grid-cols-[minmax(0,1fr)_auto] items-center gap-[8px] rounded-[12px] border px-[10px] py-[9px] text-left transition-[background,border-color,color] duration-[180ms] ease-in-out"
              :class="[
                settingsStore.isDark
                  ? 'border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.62)] text-[rgba(226,232,240,0.96)] hover:border-[rgba(96,165,250,0.42)] hover:bg-[rgba(30,41,59,0.86)]'
                  : 'border-[rgba(148,163,184,0.24)] bg-[rgba(255,255,255,0.88)] text-[rgba(51,65,85,0.96)] hover:border-[rgba(37,99,235,0.36)] hover:bg-[rgba(239,246,255,0.92)]',
                currentPath === path
                  ? settingsStore.isDark
                    ? 'border-[rgba(96,165,250,0.7)] bg-[rgba(37,99,235,0.18)] text-white'
                    : 'border-[rgba(59,130,246,0.34)] bg-[rgba(219,234,254,0.68)] text-[#1d4ed8]'
                  : '',
              ]"
            >
              <button
                type="button"
                class="btn-reset truncate-line min-w-0 text-left"
                :title="path"
                @click="emit('navigate', path)"
              >
                {{ formatFavoritePath(path) }}
              </button>
              <NButton
                quaternary
                round
                size="tiny"
                class="opacity-70 transition-opacity group-hover:opacity-100"
                @click.stop="emit('remove', path)"
              >
                <template #icon>
                  <NIcon>
                    <Close />
                  </NIcon>
                </template>
              </NButton>
            </div>
          </div>
        </NScrollbar>
      </div>
    </aside>

    <div class="pointer-events-none absolute right-[16px] top-1/2 z-2 -translate-y-1/2">
      <NTooltip placement="right">
        <template #trigger>
          <div
            class="favorite-sidebar-handle pointer-events-auto inline-flex h-[24px] w-[24px] translate-x-1/2 items-center justify-center rounded-full p-0 text-inherit transition-[transform,background-color,box-shadow,color] duration-[180ms] ease-in-out hover:scale-105"
            :class="
              settingsStore.isDark
                ? 'bg-[rgba(15,23,42,0.96)] text-[rgba(148,163,184,0.96)] shadow-[0_2px_4px_rgba(2,6,23,0.22)] hover:bg-[rgba(30,41,59,0.98)] hover:text-[rgba(191,219,254,0.96)]'
                : 'bg-[rgba(255,255,255,0.98)] text-[rgba(100,116,139,0.96)] shadow-[0_2px_4px_rgba(15,23,42,0.12)] hover:bg-[rgba(255,255,255,1)] hover:text-[rgba(37,99,235,0.96)]'
            "
            @click="emit('toggleVisibility')"
          >
            <NIcon size="16">
              <component :is="visible ? ChevronLeft : ChevronRight" />
            </NIcon>
          </div>
        </template>
        {{ handleTooltip }}
      </NTooltip>
    </div>
  </div>
</template>


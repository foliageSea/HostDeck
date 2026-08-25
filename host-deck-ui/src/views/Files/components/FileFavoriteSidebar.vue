<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from 'vue'
import { ChevronLeft, ChevronRight, Close } from '@vicons/carbon'
import { useSettingsStore } from '@/stores/settings'
import { basename } from '@/utils/path'
import FileDirectoryTree from './FileDirectoryTree.vue'

const props = defineProps<{
  connectionId?: string | null
  currentPath: string
  favoritePaths: string[]
  visible: boolean
  width: number
}>()

const emit = defineEmits<{
  navigate: [path: string]
  remove: [path: string]
  toggleVisibility: []
  'update:width': [width: number]
}>()

const MIN_WIDTH = 220
const MAX_WIDTH = 480
const settingsStore = useSettingsStore()
const activeView = ref<'tree' | 'favorites'>('tree')
const isResizing = ref(false)
let resizeStartClientX = 0
let resizeStartWidth = 0
let previousBodyCursor = ''
let previousBodyUserSelect = ''

const handleTooltip = computed(() => (props.visible ? '收起目录侧栏' : '展开目录侧栏'))
const normalizedWidth = computed(() => {
  const width = Number.isFinite(props.width) ? props.width : 252
  return Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, width))
})

function formatFavoritePath(path: string) {
  return basename(path) || '根目录'
}

function handleResize(event: PointerEvent) {
  if (!isResizing.value) {
    return
  }

  const width = resizeStartWidth + event.clientX - resizeStartClientX
  emit('update:width', Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, Math.round(width))))
}

function stopResize() {
  if (!isResizing.value) {
    return
  }

  isResizing.value = false
  window.removeEventListener('pointermove', handleResize)
  window.removeEventListener('pointerup', stopResize)
  window.removeEventListener('pointercancel', stopResize)
  document.body.style.cursor = previousBodyCursor
  document.body.style.userSelect = previousBodyUserSelect
}

function startResize(event: PointerEvent) {
  if (!props.visible || event.button !== 0) {
    return
  }

  event.preventDefault()
  event.stopPropagation()
  isResizing.value = true
  resizeStartClientX = event.clientX
  resizeStartWidth = normalizedWidth.value
  previousBodyCursor = document.body.style.cursor
  previousBodyUserSelect = document.body.style.userSelect
  document.body.style.cursor = 'col-resize'
  document.body.style.userSelect = 'none'
  window.addEventListener('pointermove', handleResize)
  window.addEventListener('pointerup', stopResize)
  window.addEventListener('pointercancel', stopResize)
}

onBeforeUnmount(stopResize)
</script>

<template>
  <div
    class="favorite-sidebar-shell relative hidden min-h-0 shrink-0 md:flex"
    :class="isResizing ? '' : 'transition-[width] duration-[220ms] ease-in-out'"
    :style="{ width: visible ? `${normalizedWidth}px` : '30px' }"
  >
    <aside
      class="app-radius-card absolute inset-y-0 left-0 flex min-w-[220px] flex-col overflow-hidden rounded-[18px] border transition-[opacity,transform] duration-[220ms] ease-in-out"
      :class="[
        settingsStore.isDark
          ? 'border-[rgba(148,163,184,0.14)] bg-[rgba(15,23,42,0.72)]'
          : 'border-[rgba(148,163,184,0.22)] bg-[rgba(248,250,252,0.84)]',
        visible ? 'translate-x-0 opacity-100' : 'pointer-events-none -translate-x-[18px] opacity-0',
      ]"
      :style="{ width: `${normalizedWidth}px` }"
    >
      <div class="px-[10px] pb-[10px] pt-[12px]">
        <div
          class="grid grid-cols-2 gap-[4px] rounded-[12px] p-[3px]"
          :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.7)]' : 'bg-[rgba(226,232,240,0.72)]'"
        >
          <button
            v-for="view in [
              { key: 'tree', label: '目录' },
              { key: 'favorites', label: `收藏 ${favoritePaths.length}` },
            ] as const"
            :key="view.key"
            type="button"
            class="btn-reset rounded-[9px] px-[8px] py-[6px] text-[12px] font-600 transition-colors"
            :class="[
              activeView === view.key
                ? settingsStore.isDark
                  ? 'bg-[rgba(51,65,85,0.92)] text-[rgba(239,246,255,0.98)]'
                  : 'bg-white text-[#1d4ed8] shadow-sm'
                : settingsStore.isDark
                  ? 'text-[rgba(148,163,184,0.92)]'
                  : 'text-[rgba(100,116,139,0.94)]',
            ]"
            @click="activeView = view.key"
          >
            {{ view.label }}
          </button>
        </div>
      </div>

      <div class="min-h-0 flex-1 px-[10px] pb-[12px]">
        <FileDirectoryTree
          v-if="activeView === 'tree'"
          :connection-id="connectionId"
          :current-path="currentPath"
          @navigate="emit('navigate', $event)"
        />
        <NEmpty
          v-else-if="favoritePaths.length === 0"
          size="small"
          description="暂无收藏"
          class="flex h-full items-center justify-center"
        />
        <NScrollbar
          v-else
          class="h-full app-scrollbar app-scrollbar-compact"
          :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'"
        >
          <div class="flex flex-col gap-[8px]">
            <div
              v-for="path in favoritePaths"
              :key="path"
              class="app-radius-item group grid w-full cursor-pointer grid-cols-[minmax(0,1fr)_auto] items-center gap-[8px] rounded-[12px] border px-[10px] py-[9px] text-left transition-[background,border-color,color] duration-[180ms] ease-in-out"
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

    <div
      v-if="visible"
      role="separator"
      aria-label="调整目录侧栏宽度"
      aria-orientation="vertical"
      :aria-valuemin="MIN_WIDTH"
      :aria-valuemax="MAX_WIDTH"
      :aria-valuenow="normalizedWidth"
      class="group absolute inset-y-[10px] right-[-5px] z-3 w-[10px] cursor-col-resize touch-none"
      @pointerdown="startResize"
    >
      <div
        class="absolute inset-y-0 left-1/2 w-[2px] -translate-x-1/2 rounded-full opacity-0 transition-opacity"
        :class="[
          settingsStore.isDark ? 'bg-[rgba(96,165,250,0.72)]' : 'bg-[rgba(37,99,235,0.58)]',
          isResizing ? 'opacity-100' : 'group-hover:opacity-100',
        ]"
      />
    </div>

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

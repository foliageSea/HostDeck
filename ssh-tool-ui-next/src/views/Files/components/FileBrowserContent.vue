<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from 'vue'
import type { FileItem } from '@/api/files'
import { useSettingsStore } from '@/stores/settings'
import { getFileIcon, getFileIconClass } from './fileIcons'

const settingsStore = useSettingsStore()

const props = defineProps<{
  files: FileItem[]
  loading: boolean
  selectedNames: string[]
  viewMode: 'list' | 'grid'
  formatFileSize: (size: number) => string
  formatModifyTime: (value?: string) => string
}>()

const emit = defineEmits<{
  clickFile: [file: FileItem, event: MouseEvent]
  contextBlank: [event: MouseEvent]
  contextFile: [file: FileItem, event: MouseEvent]
  openFile: [file: FileItem]
  selectNames: [names: string[]]
}>()

interface SelectionState {
  active: boolean
  append: boolean
  baseNames: string[]
  pointerId: number
  startX: number
  startY: number
  currentX: number
  currentY: number
}

const contentRef = ref<HTMLElement | null>(null)
const selectionState = ref<SelectionState | null>(null)

const selectionBoxStyle = computed(() => {
  const state = selectionState.value
  const content = contentRef.value
  if (!state?.active || !content) {
    return {}
  }

  const contentRect = content.getBoundingClientRect()
  const left = Math.min(state.startX, state.currentX) - contentRect.left + content.scrollLeft
  const top = Math.min(state.startY, state.currentY) - contentRect.top + content.scrollTop
  const width = Math.abs(state.currentX - state.startX)
  const height = Math.abs(state.currentY - state.startY)

  return {
    left: `${left}px`,
    top: `${top}px`,
    width: `${width}px`,
    height: `${height}px`,
  }
})

function isFileTarget(target: EventTarget | null) {
  return target instanceof Element && Boolean(target.closest('[data-file-name]'))
}

function isRectIntersecting(left: DOMRect, right: DOMRect) {
  return left.left < right.right && left.right > right.left && left.top < right.bottom && left.bottom > right.top
}

function getNamesInsideSelection(state: SelectionState) {
  const content = contentRef.value
  if (!content) {
    return []
  }

  const selectionRect = new DOMRect(
    Math.min(state.startX, state.currentX),
    Math.min(state.startY, state.currentY),
    Math.abs(state.currentX - state.startX),
    Math.abs(state.currentY - state.startY),
  )

  const nextNames: string[] = []
  content.querySelectorAll<HTMLElement>('[data-file-name]').forEach((element) => {
    if (isRectIntersecting(selectionRect, element.getBoundingClientRect())) {
      const fileName = element.dataset.fileName
      if (fileName) {
        nextNames.push(fileName)
      }
    }
  })

  return nextNames
}

function emitSelection(state: SelectionState) {
  const selectedNames = getNamesInsideSelection(state)
  if (!state.append) {
    emit('selectNames', selectedNames)
    return
  }

  emit('selectNames', Array.from(new Set([...state.baseNames, ...selectedNames])))
}

function handlePointerDown(event: PointerEvent) {
  if (event.button !== 0 || props.loading || isFileTarget(event.target)) {
    return
  }

  const target = event.currentTarget
  if (!(target instanceof HTMLElement)) {
    return
  }

  target.setPointerCapture(event.pointerId)
  selectionState.value = {
    active: false,
    append: event.ctrlKey || event.metaKey,
    baseNames: [...props.selectedNames],
    pointerId: event.pointerId,
    startX: event.clientX,
    startY: event.clientY,
    currentX: event.clientX,
    currentY: event.clientY,
  }
}

function handlePointerMove(event: PointerEvent) {
  const state = selectionState.value
  if (!state || state.pointerId !== event.pointerId) {
    return
  }

  state.currentX = event.clientX
  state.currentY = event.clientY

  if (!state.active && Math.hypot(state.currentX - state.startX, state.currentY - state.startY) >= 4) {
    state.active = true
  }

  if (state.active) {
    emitSelection(state)
  }
}

function finishSelection(event: PointerEvent) {
  const state = selectionState.value
  if (!state || state.pointerId !== event.pointerId) {
    return
  }

  if (event.currentTarget instanceof HTMLElement && event.currentTarget.hasPointerCapture(event.pointerId)) {
    event.currentTarget.releasePointerCapture(event.pointerId)
  }

  if (!state.active && !state.append) {
    emit('selectNames', [])
  }

  selectionState.value = null
}

function handleFileContextMenu(file: FileItem, event: MouseEvent) {
  event.preventDefault()
  emit('contextFile', file, event)
}

function handleBlankContextMenu(event: MouseEvent) {
  if (isFileTarget(event.target)) {
    return
  }

  event.preventDefault()
  emit('contextBlank', event)
}

onBeforeUnmount(() => {
  selectionState.value = null
})
</script>

<template>
  <div
    ref="contentRef"
    class="files-content relative min-h-0 flex-1 overflow-auto p-[4px]"
    :class="[
      settingsStore.isDark ? 'app-scrollbar app-scrollbar-dark' : 'app-scrollbar app-scrollbar-light files-content-light',
      { 'select-none': selectionState?.active },
    ]"
    @contextmenu="handleBlankContextMenu"
    @pointercancel="finishSelection"
    @pointerdown="handlePointerDown"
    @pointermove="handlePointerMove"
    @pointerup="finishSelection"
  >
    <div v-if="loading" class="flex h-full min-h-[260px] items-center justify-center">
      <NSpin size="large" />
    </div>

    <template v-else>
      <NEmpty v-if="files.length === 0" description="当前目录没有文件" class="flex h-full min-h-[260px] items-center justify-center" />

      <div v-else-if="viewMode === 'grid'" class="grid grid-cols-[repeat(auto-fill,minmax(148px,1fr))] gap-[12px]">
        <button
          v-for="file in files"
          :key="file.filename"
          :data-file-name="file.filename"
          type="button"
          class="flex min-h-[130px] flex-col items-center justify-center gap-[10px] rounded-[16px] border p-[14px] text-center text-inherit transition duration-[160ms] ease-in-out cursor-pointer"
          :class="[
            settingsStore.isDark
              ? 'border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.62)] hover:border-[rgba(96,165,250,0.55)] hover:bg-[rgba(30,41,59,0.86)]'
              : 'border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.84)] hover:border-[rgba(59,130,246,0.34)] hover:bg-[rgba(219,234,254,0.68)]',
            selectedNames.includes(file.filename)
              ? settingsStore.isDark
                ? 'border-[rgba(96,165,250,0.55)] bg-[rgba(30,41,59,0.86)]'
                : 'border-[rgba(59,130,246,0.34)] bg-[rgba(219,234,254,0.68)]'
              : '',
          ]"
          @click="emit('clickFile', file, $event)"
          @contextmenu="handleFileContextMenu(file, $event)"
          @dblclick="emit('openFile', file)"
        >
          <NIcon size="28" class="flex-none" :class="getFileIconClass(file)">
            <component :is="getFileIcon(file).icon" />
          </NIcon>
          <div class="max-w-full truncate-line">{{ file.filename }}</div>
          <div class="text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.92)]'">{{ file.isDirectory ? '目录' : formatFileSize(file.size) }}</div>
        </button>
      </div>

      <div v-else class="flex flex-col gap-[8px]">
        <button
          v-for="file in files"
          :key="file.filename"
          :data-file-name="file.filename"
          type="button"
          class="file-row grid grid-cols-[minmax(0,1fr)_120px_180px] items-center gap-[12px] rounded-[14px] border px-[14px] py-[12px] text-left text-inherit transition duration-[160ms] ease-in-out cursor-pointer"
          :class="[
            settingsStore.isDark
              ? 'border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.62)] hover:border-[rgba(96,165,250,0.55)] hover:bg-[rgba(30,41,59,0.86)]'
              : 'border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.84)] hover:border-[rgba(59,130,246,0.34)] hover:bg-[rgba(219,234,254,0.68)]',
            selectedNames.includes(file.filename)
              ? settingsStore.isDark
                ? 'border-[rgba(96,165,250,0.55)] bg-[rgba(30,41,59,0.86)]'
                : 'border-[rgba(59,130,246,0.34)] bg-[rgba(219,234,254,0.68)]'
              : '',
          ]"
          @click="emit('clickFile', file, $event)"
          @contextmenu="handleFileContextMenu(file, $event)"
          @dblclick="emit('openFile', file)"
        >
          <div class="flex min-w-0 items-center gap-[10px]">
            <NIcon size="20" class="flex-none" :class="getFileIconClass(file)">
              <component :is="getFileIcon(file).icon" />
            </NIcon>
            <span class="truncate-line">{{ file.filename }}</span>
          </div>
          <span class="file-row-size text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.92)]'">{{ file.isDirectory ? '-' : formatFileSize(file.size) }}</span>
          <span class="file-row-time text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(100,116,139,0.92)]'">{{ formatModifyTime(file.modifyTime) }}</span>
        </button>
      </div>
    </template>

    <div v-if="selectionState?.active" class="pointer-events-none absolute z-5 rounded-[8px] border border-[rgba(96,165,250,0.72)] bg-[rgba(96,165,250,0.16)] shadow-[inset_0_0_0_1px_rgba(96,165,250,0.16)]" :style="selectionBoxStyle" />
  </div>
</template>

<style scoped>
.file-icon-folder {
  color: rgba(96, 165, 250, 0.96);
}

.file-icon-image {
  color: rgba(192, 132, 252, 0.96);
}

.file-icon-video {
  color: rgba(251, 113, 133, 0.96);
}

.file-icon-audio {
  color: rgba(52, 211, 153, 0.96);
}

.file-icon-code {
  color: rgba(34, 211, 238, 0.96);
}

.file-icon-document {
  color: rgba(165, 180, 252, 0.96);
}

.file-icon-archive {
  color: rgba(251, 146, 60, 0.96);
}

.file-icon-data {
  color: rgba(250, 204, 21, 0.96);
}

.file-icon-secure {
  color: rgba(251, 191, 36, 0.96);
}

.file-icon-default {
  color: rgba(148, 163, 184, 0.96);
}

.files-content-light .file-icon-folder {
  color: rgba(37, 99, 235, 0.94);
}

.files-content-light .file-icon-image {
  color: rgba(147, 51, 234, 0.94);
}

.files-content-light .file-icon-video {
  color: rgba(225, 29, 72, 0.94);
}

.files-content-light .file-icon-audio {
  color: rgba(5, 150, 105, 0.94);
}

.files-content-light .file-icon-code {
  color: rgba(8, 145, 178, 0.94);
}

.files-content-light .file-icon-document {
  color: rgba(79, 70, 229, 0.94);
}

.files-content-light .file-icon-archive {
  color: rgba(234, 88, 12, 0.94);
}

.files-content-light .file-icon-data {
  color: rgba(202, 138, 4, 0.94);
}

.files-content-light .file-icon-secure {
  color: rgba(180, 83, 9, 0.94);
}

.files-content-light .file-icon-default {
  color: rgba(100, 116, 139, 0.94);
}

@media (max-width: 860px) {
  .file-row {
    grid-template-columns: minmax(0, 1fr);
  }

  .file-row-size,
  .file-row-time {
    display: none;
  }
}
</style>

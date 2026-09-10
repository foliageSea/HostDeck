<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { ChevronRight, FolderOpen, LoaderCircle, RefreshCw } from '@lucide/vue'
import { filesApi, type FileItem } from '@/api/files'
import type { FileSortDirection, FileSortKey } from '@/stores/file'
import { useSettingsStore } from '@/stores/settings'
import { resolve } from '@/utils/path'
import FileMediaPreview from './FileMediaPreview.vue'

interface FileColumn {
  error: boolean
  files: FileItem[]
  loading: boolean
  path: string
}

const props = defineProps<{
  connectionId?: string | null
  currentPath: string
  search: string
  selectedNames: string[]
  selectionPath: string
  sortDirection: FileSortDirection
  sortKey: FileSortKey
}>()

const emit = defineEmits<{
  activateDirectory: [path: string]
  clickFile: [path: string, files: FileItem[], file: FileItem, event: MouseEvent]
  clearSelection: []
  contextBlank: [path: string, event: MouseEvent]
  contextFile: [path: string, files: FileItem[], file: FileItem, event: MouseEvent]
  openFile: [path: string, files: FileItem[], file: FileItem]
}>()

const settingsStore = useSettingsStore()
const columns = ref<FileColumn[]>([])
const scrollerRef = ref<HTMLElement | null>(null)
const loadGeneration = ref(0)
const columnWidths = ref<Record<string, number>>({})
let resizeState: { path: string; startX: number; startWidth: number } | null = null

function pathChain(path: string) {
  const segments = path.split('/').filter(Boolean)
  return ['/', ...segments.map((_, index) => `/${segments.slice(0, index + 1).join('/')}`)]
}

function compare(left: FileItem, right: FileItem) {
  if (left.isDirectory !== right.isDirectory) return left.isDirectory ? -1 : 1
  let result = 0
  if (props.sortKey === 'size') result = left.size - right.size
  else if (props.sortKey === 'modifyTime') {
    result = new Date(left.modifyTime ?? 0).getTime() - new Date(right.modifyTime ?? 0).getTime()
  } else result = left.filename.localeCompare(right.filename)
  return props.sortDirection === 'asc' ? result : -result
}

function displayFiles(column: FileColumn) {
  const keyword = column.path === props.currentPath ? props.search.trim().toLowerCase() : ''
  return [...column.files]
    .filter((file) => file.filename !== '.' && file.filename !== '..')
    .filter((file) => !keyword || file.filename.toLowerCase().includes(keyword))
    .sort(compare)
}

async function loadPath(path: string, generation: number) {
  if (!props.connectionId) return null
  try {
    return await filesApi.list(props.connectionId, path)
  } catch (error) {
    console.error(`Failed to load file column ${path}`, error)
    return null
  } finally {
    if (generation !== loadGeneration.value) return
  }
}

async function rebuildColumns() {
  const generation = ++loadGeneration.value
  const paths = pathChain(props.currentPath)
  const cached = new Map(columns.value.map((column) => [column.path, column.files]))
  columns.value = paths.map((path) => ({
    error: false,
    files: cached.get(path) ?? [],
    loading: !cached.has(path),
    path,
  }))

  for (const column of columns.value) {
    if (!column.loading) continue
    const files = await loadPath(column.path, generation)
    if (generation !== loadGeneration.value) return
    column.loading = false
    column.error = files === null
    column.files = files ?? []
  }
  await scrollToEnd()
}

async function refresh() {
  const generation = ++loadGeneration.value
  for (const column of columns.value) {
    column.loading = true
    const files = await loadPath(column.path, generation)
    if (generation !== loadGeneration.value) return
    column.loading = false
    column.error = files === null
    column.files = files ?? []
  }
}

async function scrollToEnd() {
  await nextTick()
  scrollerRef.value?.scrollTo?.({ left: scrollerRef.value.scrollWidth, behavior: 'smooth' })
}

function getColumnWidth(path: string) {
  return columnWidths.value[path] ?? 260
}

function startColumnResize(path: string, event: PointerEvent) {
  event.preventDefault()
  resizeState = { path, startX: event.clientX, startWidth: getColumnWidth(path) }
  window.addEventListener('pointermove', resizeColumn)
  window.addEventListener('pointerup', stopColumnResize, { once: true })
}

function resizeColumn(event: PointerEvent) {
  if (!resizeState) return
  const width = Math.min(
    520,
    Math.max(180, resizeState.startWidth + event.clientX - resizeState.startX),
  )
  columnWidths.value = { ...columnWidths.value, [resizeState.path]: width }
}

function stopColumnResize() {
  resizeState = null
  window.removeEventListener('pointermove', resizeColumn)
}

function handleWheel(event: WheelEvent) {
  if (!event.shiftKey || !scrollerRef.value) return
  event.preventDefault()
  scrollerRef.value.scrollLeft += event.deltaY
}

function isSelected(column: FileColumn, file: FileItem) {
  return column.path === props.selectionPath && props.selectedNames.includes(file.filename)
}

function isActiveDirectory(column: FileColumn, file: FileItem) {
  return file.isDirectory && resolve(column.path, file.filename) === props.currentPath
}

function isExpanded(column: FileColumn, file: FileItem) {
  if (!file.isDirectory) return false
  const filePath = resolve(column.path, file.filename)
  return props.currentPath.startsWith(`${filePath}/`)
}

function handleClick(column: FileColumn, file: FileItem, event: MouseEvent) {
  emit('clickFile', column.path, column.files, file, event)
  if (file.isDirectory && !event.ctrlKey && !event.metaKey && !event.shiftKey) {
    emit('activateDirectory', resolve(column.path, file.filename))
  }
}

function handleBlankContext(column: FileColumn, event: MouseEvent) {
  if (event.target instanceof Element && event.target.closest('[data-file-name]')) return
  event.preventDefault()
  emit('contextBlank', column.path, event)
}

defineExpose({ refresh })

watch(() => [props.connectionId, props.currentPath], rebuildColumns)
onMounted(rebuildColumns)
onBeforeUnmount(stopColumnResize)
</script>

<template>
  <div
    ref="scrollerRef"
    data-testid="file-column-browser"
    class="file-column-scroller app-radius-surface min-h-0 flex-1 overflow-x-scroll overflow-y-hidden rounded-[8px] border"
    :class="
      settingsStore.isDark
        ? 'app-scrollbar app-scrollbar-dark border-[rgba(148,163,184,0.2)] bg-[rgba(15,23,42,0.32)]'
        : 'app-scrollbar app-scrollbar-light border-[rgba(148,163,184,0.3)] bg-[rgba(255,255,255,0.52)]'
    "
    @wheel="handleWheel"
  >
    <div class="flex h-full min-w-max pb-[2px]">
      <section
        v-for="column in columns"
        :key="column.path"
        class="relative flex h-full flex-none flex-col border-r"
        :class="
          settingsStore.isDark
            ? 'border-[rgba(148,163,184,0.18)]'
            : 'border-[rgba(148,163,184,0.28)]'
        "
        :style="{ width: `${getColumnWidth(column.path)}px` }"
        @click.self="emit('clearSelection')"
        @contextmenu="handleBlankContext(column, $event)"
      >
        <header
          class="flex h-[38px] flex-none items-center gap-[7px] border-b px-[11px] text-[12px] font-600"
          :class="
            settingsStore.isDark
              ? 'border-[rgba(148,163,184,0.16)] text-slate-300'
              : 'border-[rgba(148,163,184,0.24)] text-slate-600'
          "
        >
          <FolderOpen :size="15" />
          <span class="min-w-0 flex-1 truncate-line">{{
            column.path === '/' ? '根目录' : column.path.split('/').at(-1)
          }}</span>
          <span class="font-400 opacity-65">{{ displayFiles(column).length }}</span>
        </header>

        <div
          class="file-column-list app-scrollbar min-h-0 flex-1 overflow-y-auto p-[5px]"
          :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'"
          @click.self="emit('clearSelection')"
        >
          <div v-if="column.loading" class="flex h-full items-center justify-center">
            <LoaderCircle class="animate-spin opacity-60" :size="21" />
          </div>
          <button
            v-else-if="column.error"
            type="button"
            class="flex h-full w-full flex-col items-center justify-center gap-[8px] text-[12px] opacity-70"
            @click="refresh"
          >
            <RefreshCw :size="20" />加载失败，点击重试
          </button>
          <div
            v-else-if="displayFiles(column).length === 0"
            class="flex h-full items-center justify-center px-[20px] text-center text-[12px] opacity-55"
          >
            {{ column.path === currentPath && search ? '没有匹配项' : '空目录' }}
          </div>
          <button
            v-for="file in displayFiles(column)"
            v-else
            :key="file.filename"
            :aria-current="isActiveDirectory(column, file) ? 'page' : undefined"
            :aria-selected="isSelected(column, file)"
            :data-file-name="file.filename"
            type="button"
            class="mb-[2px] grid h-[36px] w-full grid-cols-[44px_minmax(0,1fr)_18px] items-center gap-[5px] border-0 rounded-[5px] px-[2px] text-left text-[13px] outline-none transition-colors"
            :class="
              isSelected(column, file) || isActiveDirectory(column, file)
                ? 'file-column-item-selected bg-[var(--app-primary-color)] text-white shadow-[0_1px_3px_rgba(0,0,0,0.18)]'
                : isExpanded(column, file)
                  ? 'bg-[var(--app-primary-soft)] text-[var(--app-primary-color)]'
                  : settingsStore.isDark
                    ? 'bg-transparent hover:bg-[rgba(51,65,85,0.78)]'
                    : 'bg-transparent hover:bg-[rgba(226,232,240,0.8)]'
            "
            @click="handleClick(column, file, $event)"
            @contextmenu.prevent="emit('contextFile', column.path, column.files, file, $event)"
            @dblclick="emit('openFile', column.path, column.files, file)"
          >
            <FileMediaPreview
              :connection-id="connectionId"
              :current-path="column.path"
              :file="file"
              variant="list"
            />
            <span class="truncate-line">{{ file.filename }}</span>
            <ChevronRight v-if="file.isDirectory" :size="15" />
          </button>
        </div>
        <div
          class="absolute inset-y-0 right-[-4px] z-10 w-[8px] touch-none cursor-col-resize"
          aria-label="调整分栏宽度"
          role="separator"
          @pointerdown="startColumnResize(column.path, $event)"
        />
      </section>
    </div>
  </div>
</template>

<style scoped>
.file-column-scroller {
  scrollbar-color: transparent transparent;
  scrollbar-width: thin;
}

.file-column-scroller:hover,
.file-column-scroller:focus-within {
  scrollbar-color: var(--app-scrollbar-thumb) transparent;
}

.file-column-scroller::-webkit-scrollbar {
  height: 8px;
}

.file-column-scroller::-webkit-scrollbar-thumb {
  background-color: transparent;
}

.file-column-scroller:hover::-webkit-scrollbar-thumb,
.file-column-scroller:focus-within::-webkit-scrollbar-thumb {
  background-color: var(--app-scrollbar-thumb);
}

.file-column-list {
  scrollbar-color: transparent transparent;
  scrollbar-width: thin;
}

.file-column-list:hover,
.file-column-list:focus-within {
  scrollbar-color: var(--app-scrollbar-thumb) transparent;
}

.file-column-list::-webkit-scrollbar {
  width: 8px;
}

.file-column-list::-webkit-scrollbar-thumb {
  background-color: transparent;
}

.file-column-list:hover::-webkit-scrollbar-thumb,
.file-column-list:focus-within::-webkit-scrollbar-thumb {
  background-color: var(--app-scrollbar-thumb);
}
</style>

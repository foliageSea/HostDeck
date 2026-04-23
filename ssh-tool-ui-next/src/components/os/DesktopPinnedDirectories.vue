<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import AppIcon from '@/components/common/AppIcon.vue'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { basename } from '@/utils/path'

const DESKTOP_ICON_DRAG_THRESHOLD = 4
const DESKTOP_ICON_HEIGHT = 108
const DESKTOP_ICON_WIDTH = 96
const DESKTOP_ICON_GAP_X = 28
const DESKTOP_ICON_GAP_Y = 28
const DESKTOP_ICON_PADDING = 20
const DRAG_SUPPRESSION_WINDOW = 240

interface DragState {
  currentX: number
  currentY: number
  moved: boolean
  path: string
  pointerId: number
  startPointerX: number
  startPointerY: number
  startX: number
  startY: number
}

interface SelectionState {
  active: boolean
  append: boolean
  basePaths: string[]
  currentX: number
  currentY: number
  pointerId: number
  startX: number
  startY: number
}

interface GridPosition {
  x: number
  y: number
}

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()

const contentRef = ref<HTMLElement | null>(null)
const contentBounds = ref({
  height: 0,
  width: 0,
})
const contextMenu = ref<{
  path?: string
  scope: 'icon' | 'selection'
  x: number
  y: number
} | null>(null)
const dragState = ref<DragState | null>(null)
const dragSuppression = ref<{
  expiresAt: number
  path: string
} | null>(null)
const selectedPaths = ref<string[]>([])
const selectionState = ref<SelectionState | null>(null)

const pinnedDirectories = computed(() => {
  const storedPositions = desktopStore.getPinnedDirectoryPositions()
  const paths = desktopStore.getPinnedDirectories()
  const occupiedIndexes = new Set<number>()
  const searchSpan = paths.length + getGridRowCount()

  return paths.map((path, index) => {
    const defaultPosition = getDefaultPosition(index)
    const storedPosition = storedPositions[path]
    const activeDrag = dragState.value?.path === path ? dragState.value : null
    const position = activeDrag
      ? { x: activeDrag.currentX, y: activeDrag.currentY }
      : storedPosition
        ? resolveGridPosition(storedPosition, occupiedIndexes, searchSpan)
        : resolveGridPosition(defaultPosition, occupiedIndexes, searchSpan)

    return {
      label: basename(path) || '根目录',
      path,
      x: position.x,
      y: position.y,
    }
  })
})
const canvasBounds = computed(() => {
  const maxRight = pinnedDirectories.value.reduce(
    (value, directory) => Math.max(value, directory.x + DESKTOP_ICON_WIDTH + DESKTOP_ICON_PADDING),
    contentBounds.value.width,
  )
  const maxBottom = pinnedDirectories.value.reduce(
    (value, directory) => Math.max(value, directory.y + DESKTOP_ICON_HEIGHT + DESKTOP_ICON_PADDING),
    contentBounds.value.height,
  )

  return {
    height: Math.max(maxBottom, contentBounds.value.height),
    width: Math.max(maxRight, contentBounds.value.width),
  }
})
const canvasStyle = computed(() => ({
  height: `${canvasBounds.value.height}px`,
  width: `${canvasBounds.value.width}px`,
}))
const dragPreviewPosition = computed(() => {
  const state = dragState.value
  if (!state?.moved) {
    return null
  }

  const desiredPosition = snapPosition(state.currentX, state.currentY)
  const occupiedIndexes = new Set(
    pinnedDirectories.value
      .filter((directory) => directory.path !== state.path)
      .map((directory) => getGridIndex(directory.x, directory.y)),
  )

  return getGridPositionByIndex(
    resolveGridIndex(getGridIndex(desiredPosition.x, desiredPosition.y), occupiedIndexes, pinnedDirectories.value.length + getGridRowCount()),
  )
})
const contextMenuOptions = computed(() => {
  if (contextMenu.value?.scope === 'icon') {
    return [
      { key: 'open', label: '新窗口打开' },
      { key: 'remove', label: '移除', props: { style: 'color: #dc2626;' } },
    ]
  }

  if (contextMenu.value?.scope === 'selection' && selectedPaths.value.length > 0) {
    return [
      { key: 'remove-selected', label: `移除所选 (${selectedPaths.value.length})`, props: { style: 'color: #dc2626;' } },
    ]
  }

  return []
})
const gridOverlayStyle = computed(() => ({
  backgroundImage: settingsStore.isDark
    ? 'radial-gradient(circle, rgba(191,219,254,0.18) 1.5px, transparent 1.5px)'
    : 'radial-gradient(circle, rgba(37,99,235,0.16) 1.5px, transparent 1.5px)',
  backgroundPosition: `${DESKTOP_ICON_PADDING + DESKTOP_ICON_WIDTH / 2}px ${DESKTOP_ICON_PADDING + DESKTOP_ICON_HEIGHT / 2}px`,
  backgroundSize: `${DESKTOP_ICON_WIDTH + DESKTOP_ICON_GAP_X}px ${DESKTOP_ICON_HEIGHT + DESKTOP_ICON_GAP_Y}px`,
}))
const selectionBoxStyle = computed(() => {
  const state = selectionState.value
  const content = contentRef.value
  if (!state?.active || !content) {
    return {}
  }

  const contentRect = content.getBoundingClientRect()
  const maxWidth = canvasBounds.value.width
  const maxHeight = canvasBounds.value.height
  const startLocalX = state.startX - contentRect.left + content.scrollLeft
  const startLocalY = state.startY - contentRect.top + content.scrollTop
  const currentLocalX = state.currentX - contentRect.left + content.scrollLeft
  const currentLocalY = state.currentY - contentRect.top + content.scrollTop
  const left = Math.max(0, Math.min(startLocalX, currentLocalX))
  const top = Math.max(0, Math.min(startLocalY, currentLocalY))
  const right = Math.min(maxWidth, Math.max(startLocalX, currentLocalX))
  const bottom = Math.min(maxHeight, Math.max(startLocalY, currentLocalY))

  return {
    height: `${Math.max(0, bottom - top)}px`,
    left: `${left}px`,
    top: `${top}px`,
    width: `${Math.max(0, right - left)}px`,
  }
})
const showContextMenu = computed(() => Boolean(contextMenu.value) && contextMenuOptions.value.length > 0)

watch(pinnedDirectories, (directories) => {
  const availablePaths = new Set(directories.map((directory) => directory.path))
  selectedPaths.value = selectedPaths.value.filter((path) => availablePaths.has(path))

  if (contextMenu.value?.path && !availablePaths.has(contextMenu.value.path)) {
    closeContextMenu()
  }
})

function closeContextMenu() {
  contextMenu.value = null
}

function clampPosition(x: number, y: number) {
  const maxX = Math.max(DESKTOP_ICON_PADDING, contentBounds.value.width - DESKTOP_ICON_WIDTH - DESKTOP_ICON_PADDING)
  const maxY = Math.max(DESKTOP_ICON_PADDING, contentBounds.value.height - DESKTOP_ICON_HEIGHT - DESKTOP_ICON_PADDING)

  return {
    x: Math.min(Math.max(x, DESKTOP_ICON_PADDING), maxX),
    y: Math.min(Math.max(y, DESKTOP_ICON_PADDING), maxY),
  }
}

function getGridRowCount() {
  const availableHeight = Math.max(
    DESKTOP_ICON_HEIGHT,
    contentBounds.value.height - DESKTOP_ICON_PADDING * 2,
  )

  return Math.max(1, Math.floor(availableHeight / (DESKTOP_ICON_HEIGHT + DESKTOP_ICON_GAP_Y)))
}

function getGridIndex(x: number, y: number) {
  const rowCount = getGridRowCount()
  const column = Math.max(0, Math.round((x - DESKTOP_ICON_PADDING) / (DESKTOP_ICON_WIDTH + DESKTOP_ICON_GAP_X)))
  const row = Math.min(
    rowCount - 1,
    Math.max(0, Math.round((y - DESKTOP_ICON_PADDING) / (DESKTOP_ICON_HEIGHT + DESKTOP_ICON_GAP_Y))),
  )

  return column * rowCount + row
}

function getGridPositionByIndex(index: number): GridPosition {
  const rowCount = getGridRowCount()
  const column = Math.max(0, Math.floor(index / rowCount))
  const row = Math.max(0, index % rowCount)

  return {
    x: DESKTOP_ICON_PADDING + column * (DESKTOP_ICON_WIDTH + DESKTOP_ICON_GAP_X),
    y: DESKTOP_ICON_PADDING + row * (DESKTOP_ICON_HEIGHT + DESKTOP_ICON_GAP_Y),
  }
}

function resolveGridIndex(preferredIndex: number, occupiedIndexes: Set<number>, searchSpan: number) {
  if (!occupiedIndexes.has(preferredIndex)) {
    return preferredIndex
  }

  const maxDistance = Math.max(searchSpan, occupiedIndexes.size + 1)
  for (let distance = 1; distance <= maxDistance; distance += 1) {
    const nextIndex = preferredIndex + distance
    if (!occupiedIndexes.has(nextIndex)) {
      return nextIndex
    }

    const previousIndex = preferredIndex - distance
    if (previousIndex >= 0 && !occupiedIndexes.has(previousIndex)) {
      return previousIndex
    }
  }

  return preferredIndex + maxDistance + 1
}

function resolveGridPosition(position: GridPosition, occupiedIndexes: Set<number>, searchSpan: number): GridPosition {
  const index = resolveGridIndex(getGridIndex(position.x, position.y), occupiedIndexes, searchSpan)
  occupiedIndexes.add(index)
  return getGridPositionByIndex(index)
}

function snapPosition(x: number, y: number) {
  const snappedX = DESKTOP_ICON_PADDING
    + Math.round((x - DESKTOP_ICON_PADDING) / (DESKTOP_ICON_WIDTH + DESKTOP_ICON_GAP_X)) * (DESKTOP_ICON_WIDTH + DESKTOP_ICON_GAP_X)
  const snappedY = DESKTOP_ICON_PADDING
    + Math.round((y - DESKTOP_ICON_PADDING) / (DESKTOP_ICON_HEIGHT + DESKTOP_ICON_GAP_Y)) * (DESKTOP_ICON_HEIGHT + DESKTOP_ICON_GAP_Y)

  return clampPosition(snappedX, snappedY)
}

function getDefaultPosition(index: number) {
  return getGridPositionByIndex(index)
}

function suppressDirectoryInteraction(path: string) {
  dragSuppression.value = {
    expiresAt: Date.now() + DRAG_SUPPRESSION_WINDOW,
    path,
  }
}

function shouldIgnoreDirectoryInteraction(path: string) {
  if (!dragSuppression.value) {
    return false
  }

  if (dragSuppression.value.expiresAt <= Date.now()) {
    dragSuppression.value = null
    return false
  }

  return dragSuppression.value.path === path
}

function isDirectorySelected(path: string) {
  return selectedPaths.value.includes(path)
}

function isDirectoryTarget(target: EventTarget | null) {
  return target instanceof Element && Boolean(target.closest('[data-directory-path]'))
}

function isRectIntersecting(left: DOMRect, right: DOMRect) {
  return left.left < right.right && left.right > right.left && left.top < right.bottom && left.bottom > right.top
}

function getPathsInsideSelection(state: SelectionState) {
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
  const nextPaths: string[] = []

  content.querySelectorAll<HTMLElement>('[data-directory-path]').forEach((element) => {
    if (!isRectIntersecting(selectionRect, element.getBoundingClientRect())) {
      return
    }

    const path = element.dataset.directoryPath
    if (path) {
      nextPaths.push(path)
    }
  })

  return nextPaths
}

function emitSelection(state: SelectionState) {
  const paths = getPathsInsideSelection(state)
  selectedPaths.value = state.append ? Array.from(new Set([...state.basePaths, ...paths])) : paths
}

function handlePointerDown(event: PointerEvent) {
  if (event.button !== 0 || isDirectoryTarget(event.target)) {
    return
  }

  closeContextMenu()
  const target = event.currentTarget
  if (!(target instanceof HTMLElement)) {
    return
  }

  target.setPointerCapture(event.pointerId)
  selectionState.value = {
    active: false,
    append: event.ctrlKey || event.metaKey,
    basePaths: [...selectedPaths.value],
    currentX: event.clientX,
    currentY: event.clientY,
    pointerId: event.pointerId,
    startX: event.clientX,
    startY: event.clientY,
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
    selectedPaths.value = []
  }

  selectionState.value = null
}

function handleDirectoryClick(path: string, event: MouseEvent) {
  if (shouldIgnoreDirectoryInteraction(path)) {
    return
  }

  closeContextMenu()

  if (event.ctrlKey || event.metaKey) {
    selectedPaths.value = isDirectorySelected(path)
      ? selectedPaths.value.filter((selectedPath) => selectedPath !== path)
      : [...selectedPaths.value, path]
    return
  }

  selectedPaths.value = [path]
}

function openDirectory(path: string) {
  if (shouldIgnoreDirectoryInteraction(path)) {
    return
  }

  selectedPaths.value = [path]
  desktopStore.openPinnedDirectory(path)
  closeContextMenu()
}

function openSelectedDirectory(path?: string) {
  const targetPath = path ?? selectedPaths.value[0]
  if (!targetPath) {
    return
  }

  openDirectory(targetPath)
}

function removeDirectories(paths: string[]) {
  if (paths.length === 0) {
    return
  }

  desktopStore.unpinDirectoryFromDesktop(paths)
  selectedPaths.value = selectedPaths.value.filter((path) => !paths.includes(path))
  closeContextMenu()
  getUiApi().message.success(paths.length === 1 ? '已从桌面移除该目录。' : `已从桌面移除 ${paths.length} 个目录。`)
}

function handleDirectoryContextMenu(path: string, event: MouseEvent) {
  event.preventDefault()

  if (!isDirectorySelected(path)) {
    selectedPaths.value = [path]
  }

  contextMenu.value = {
    path,
    scope: 'icon',
    x: event.clientX,
    y: event.clientY,
  }
}

function handleBlankContextMenu(event: MouseEvent) {
  if (isDirectoryTarget(event.target)) {
    return
  }

  event.preventDefault()
  closeContextMenu()

  if (selectedPaths.value.length === 0) {
    return
  }

  contextMenu.value = {
    scope: 'selection',
    x: event.clientX,
    y: event.clientY,
  }
}

function updateContentBounds() {
  const content = contentRef.value
  if (!content) {
    return
  }

  contentBounds.value = {
    height: content.clientHeight,
    width: content.clientWidth,
  }
}

function handleDirectoryPointerDown(directory: { path: string; x: number; y: number }, event: PointerEvent) {
  if (event.button !== 0 || event.ctrlKey || event.metaKey) {
    return
  }

  closeContextMenu()
  selectedPaths.value = [directory.path]

  const target = event.currentTarget
  if (!(target instanceof HTMLElement)) {
    return
  }

  target.setPointerCapture(event.pointerId)
  dragState.value = {
    currentX: directory.x,
    currentY: directory.y,
    moved: false,
    path: directory.path,
    pointerId: event.pointerId,
    startPointerX: event.clientX,
    startPointerY: event.clientY,
    startX: directory.x,
    startY: directory.y,
  }
}

function handleDirectoryPointerMove(event: PointerEvent) {
  const state = dragState.value
  if (!state || state.pointerId !== event.pointerId) {
    return
  }

  const deltaX = event.clientX - state.startPointerX
  const deltaY = event.clientY - state.startPointerY
  const moved = Math.hypot(deltaX, deltaY) >= DESKTOP_ICON_DRAG_THRESHOLD

  state.moved = state.moved || moved
  if (!state.moved) {
    return
  }

  const nextPosition = clampPosition(state.startX + deltaX, state.startY + deltaY)
  state.currentX = nextPosition.x
  state.currentY = nextPosition.y
}

function finishDirectoryDrag(event: PointerEvent) {
  const state = dragState.value
  if (!state || state.pointerId !== event.pointerId) {
    return
  }

  if (event.currentTarget instanceof HTMLElement && event.currentTarget.hasPointerCapture(event.pointerId)) {
    event.currentTarget.releasePointerCapture(event.pointerId)
  }

  if (state.moved) {
    const snappedPosition = dragPreviewPosition.value ?? snapPosition(state.currentX, state.currentY)
    desktopStore.setPinnedDirectoryPosition(state.path, snappedPosition.x, snappedPosition.y)
    suppressDirectoryInteraction(state.path)
  }

  dragState.value = null
}

function handleContextMenuSelect(key: string | number) {
  if (key === 'open') {
    openSelectedDirectory(contextMenu.value?.path)
    return
  }

  if (key === 'remove') {
    removeDirectories(contextMenu.value?.path && isDirectorySelected(contextMenu.value.path)
      ? [...selectedPaths.value]
      : contextMenu.value?.path ? [contextMenu.value.path] : [])
    return
  }

  if (key === 'remove-selected') {
    removeDirectories([...selectedPaths.value])
    return
  }

  closeContextMenu()
}

onMounted(() => {
  updateContentBounds()
  window.addEventListener('resize', updateContentBounds)
})

onUnmounted(() => {
  window.removeEventListener('resize', updateContentBounds)
  dragState.value = null
  selectionState.value = null
})
</script>

<template>
  <div
    ref="contentRef"
    class="absolute inset-0 z-[5] overflow-auto"
    @contextmenu="handleBlankContextMenu"
    @pointercancel="finishSelection"
    @pointerdown="handlePointerDown"
    @pointermove="handlePointerMove"
    @pointerup="finishSelection"
  >
    <div class="relative min-h-full min-w-full" :style="canvasStyle">
      <div
        v-if="dragPreviewPosition"
        class="pointer-events-none absolute inset-0 z-[4] opacity-100"
        :style="gridOverlayStyle"
      />

      <div
        v-if="dragPreviewPosition"
        class="pointer-events-none absolute z-[6] rounded-[18px] border border-dashed border-[rgba(96,165,250,0.72)] bg-[rgba(96,165,250,0.12)] shadow-[0_0_0_1px_rgba(96,165,250,0.12)]"
        :style="{
          left: `${dragPreviewPosition.x}px`,
          top: `${dragPreviewPosition.y}px`,
          width: `${DESKTOP_ICON_WIDTH}px`,
          minHeight: `${DESKTOP_ICON_HEIGHT}px`,
        }"
      />

      <button
        v-for="directory in pinnedDirectories"
        :key="directory.path"
        :data-directory-path="directory.path"
        type="button"
        class="group absolute flex min-h-[108px] w-[96px] flex-col items-center justify-center gap-[10px] rounded-[18px] border px-[10px] py-[12px] text-center text-inherit transition-[background-color,border-color,transform,box-shadow] duration-[180ms] ease-in-out cursor-pointer"
        :class="[
          settingsStore.isDark
            ? 'border-[rgba(148,163,184,0.12)] bg-[rgba(15,23,42,0.18)] text-[#e2e8f0] hover:border-[rgba(96,165,250,0.3)] hover:bg-[rgba(30,41,59,0.52)]'
            : 'border-[rgba(148,163,184,0.18)] bg-[rgba(255,255,255,0.22)] text-[#0f172a] hover:border-[rgba(59,130,246,0.24)] hover:bg-[rgba(255,255,255,0.46)]',
          isDirectorySelected(directory.path)
            ? settingsStore.isDark
              ? 'border-[rgba(96,165,250,0.56)] bg-[rgba(30,41,59,0.76)] shadow-[0_18px_36px_rgba(2,6,23,0.22)]'
              : 'border-[rgba(59,130,246,0.34)] bg-[rgba(219,234,254,0.68)] shadow-[0_16px_32px_rgba(59,130,246,0.14)]'
            : '',
          dragState?.path === directory.path ? 'z-[7] cursor-grabbing opacity-80 shadow-[0_20px_40px_rgba(15,23,42,0.18)] transition-none' : '',
        ]"
        :style="{
          left: `${directory.x}px`,
          top: `${directory.y}px`,
        }"
        @click.stop="handleDirectoryClick(directory.path, $event)"
        @contextmenu.stop="handleDirectoryContextMenu(directory.path, $event)"
        @dblclick.stop="openDirectory(directory.path)"
        @pointerdown.stop="handleDirectoryPointerDown(directory, $event)"
        @pointermove.stop="handleDirectoryPointerMove($event)"
        @pointerup.stop="finishDirectoryDrag($event)"
        @pointercancel.stop="finishDirectoryDrag($event)"
      >
        <div
          class="flex h-[52px] w-[52px] items-center justify-center rounded-[16px] transition-[transform,background-color] duration-[180ms] ease-in-out group-hover:scale-[1.03]"
          :class="settingsStore.isDark ? 'bg-[rgba(30,41,59,0.84)]' : 'bg-[rgba(255,255,255,0.72)]'"
        >
          <AppIcon name="folder" :size="28" />
        </div>
        <div class="w-full">
          <div class="truncate-line text-[13px] font-600">{{ directory.label }}</div>
        </div>
      </button>

      <div
        v-if="selectionState?.active"
        class="pointer-events-none absolute z-[6] rounded-[10px] border border-[rgba(96,165,250,0.72)] bg-[rgba(96,165,250,0.16)] shadow-[inset_0_0_0_1px_rgba(96,165,250,0.16)]"
        :style="selectionBoxStyle"
      />
    </div>

    <NDropdown
      placement="bottom-start"
      trigger="manual"
      :show="showContextMenu"
      :x="contextMenu?.x ?? 0"
      :y="contextMenu?.y ?? 0"
      :options="contextMenuOptions"
      @clickoutside="closeContextMenu"
      @select="handleContextMenuSelect"
    />
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { ExternalLink } from '@lucide/vue'
import DesktopMenu from './DesktopMenu.vue'
import type { DesktopMenuOption } from './menu-options'
import {
  DESKTOP_GRID_PADDING,
  clampDesktopGridPosition,
  getDesktopGridCellAtPosition,
  getDesktopGridPosition,
  getDesktopGridSpan,
  occupyDesktopGridCells,
  resolveDesktopGridCell,
  snapDesktopGridPosition,
  type DesktopGridCellKey,
} from '../core/desktop-grid'
import {
  useDesktopContext,
  useDesktop as useDesktopStore,
  useDesktopPreferences as useSettingsStore,
} from './context'

const dragThreshold = 4
let detailsRequestId = 0

interface DragState {
  currentX: number
  currentY: number
  id: string
  moved: boolean
  pointerId: number
  startPointerX: number
  startPointerY: number
  startX: number
  startY: number
}

interface SettlingState {
  id: string
  offsetX: number
  offsetY: number
}

const props = defineProps<{
  blockedGridCells?: DesktopGridCellKey[]
}>()
const desktopStore = useDesktopStore()
const context = useDesktopContext()
const widgetStore = (() => {
  if (!context.widgets)
    throw new Error('DesktopWidgets requires a widget runtime in DesktopContext.')
  return context.widgets
})()
const desktopWidgetDefinitions = widgetStore.definitions
const settingsStore = useSettingsStore()
const layerRef = ref<HTMLElement | null>(null)
const bounds = ref({ height: 0, width: 0 })
let resizeObserver: ResizeObserver | undefined
const contextMenu = ref<{ id: string; x: number; y: number } | null>(null)
const dragState = ref<DragState | null>(null)
const settlingState = ref<SettlingState | null>(null)

const renderedWidgets = computed(() =>
  (() => {
    const occupiedCells = new Set<DesktopGridCellKey>(props.blockedGridCells ?? [])

    return widgetStore.widgets.map((widget) => {
      const definition = desktopWidgetDefinitions[widget.type]
      const width =
        bounds.value.width > 0
          ? Math.min(definition.width, Math.max(0, bounds.value.width - DESKTOP_GRID_PADDING * 2))
          : definition.width
      const maxX = Math.max(DESKTOP_GRID_PADDING, bounds.value.width - width - DESKTOP_GRID_PADDING)
      const maxY = Math.max(
        DESKTOP_GRID_PADDING,
        bounds.value.height - definition.height - DESKTOP_GRID_PADDING,
      )
      const drag = dragState.value?.id === widget.id ? dragState.value : null
      const desiredPosition = {
        x: drag?.currentX ?? widget.x ?? maxX,
        y: drag?.currentY ?? widget.y ?? DESKTOP_GRID_PADDING,
      }
      const snappedPosition = snapDesktopGridPosition(
        desiredPosition.x,
        desiredPosition.y,
        width,
        definition.height,
        bounds.value.width,
        bounds.value.height,
      )
      const span = getDesktopGridSpan(width, definition.height)
      const cell = resolveDesktopGridCell(
        getDesktopGridCellAtPosition(snappedPosition.x, snappedPosition.y, bounds.value.height),
        span,
        occupiedCells,
        bounds.value.height,
        widgetStore.widgets.length + 1,
      )
      occupyDesktopGridCells(occupiedCells, cell, span)
      const position = getDesktopGridPosition(cell)
      const dropX =
        desiredPosition.x >= maxX
          ? maxX
          : Math.min(maxX, Math.max(DESKTOP_GRID_PADDING, position.x))
      const dropY =
        desiredPosition.y >= maxY
          ? maxY
          : Math.min(maxY, Math.max(DESKTOP_GRID_PADDING, position.y))

      return {
        definition,
        dragOffsetX: drag ? drag.currentX - drag.startX : 0,
        dragOffsetY: drag ? drag.currentY - drag.startY : 0,
        dropX,
        dropY,
        instance: widget,
        width,
        x: drag?.startX ?? dropX,
        y: drag?.startY ?? dropY,
      }
    })
  })(),
)
const dragPreview = computed(() => {
  if (!dragState.value?.moved) return null
  const widget = getRenderedWidget(dragState.value.id)
  if (!widget) return null

  return {
    height: widget.definition.height,
    width: widget.width,
    x: widget.dropX,
    y: widget.dropY,
  }
})
const contextMenuOptions = computed<DesktopMenuOption[]>(() => {
  const widget = widgetStore.widgets.find((item) => item.id === contextMenu.value?.id)
  if (!widget) return []
  const definition = desktopWidgetDefinitions[widget.type]
  return [
    ...(definition.detailsAppId ? [{ key: 'details', label: '查看详情' }] : []),
    { key: 'remove', label: '移除小组件', danger: true },
  ]
})

function updateBounds() {
  const layer = layerRef.value
  if (!layer) return
  bounds.value = {
    height: layer.clientHeight,
    width: layer.clientWidth,
  }
}

function getRenderedWidget(id: string) {
  return renderedWidgets.value.find((widget) => widget.instance.id === id)
}

function openDetails(id: string) {
  const widget = widgetStore.widgets.find((item) => item.id === id)
  if (!widget) return
  const appId = desktopWidgetDefinitions[widget.type].detailsAppId
  const detailsProps = desktopWidgetDefinitions[widget.type].detailsProps
  if (appId) {
    const windowId = desktopStore.openWindow(appId, detailsProps)
    if (windowId && detailsProps) {
      desktopStore.updateWindowProps(windowId, {
        ...detailsProps,
        viewRequestId: ++detailsRequestId,
      })
    }
  }
  contextMenu.value = null
}

function startDrag(id: string, event: PointerEvent) {
  if (event.button !== 0) return
  const widget = getRenderedWidget(id)
  if (!widget) return

  if (event.currentTarget instanceof HTMLElement) {
    event.currentTarget.setPointerCapture?.(event.pointerId)
  }
  contextMenu.value = null
  settlingState.value = null
  dragState.value = {
    currentX: widget.x,
    currentY: widget.y,
    id,
    moved: false,
    pointerId: event.pointerId,
    startPointerX: event.clientX,
    startPointerY: event.clientY,
    startX: widget.x,
    startY: widget.y,
  }
}

function updateDragPosition(state: DragState, clientX: number, clientY: number) {
  const deltaX = clientX - state.startPointerX
  const deltaY = clientY - state.startPointerY
  state.moved = state.moved || Math.hypot(deltaX, deltaY) >= dragThreshold
  if (!state.moved) return

  const widget = getRenderedWidget(state.id)
  if (!widget) return
  const position = clampDesktopGridPosition(
    state.startX + deltaX,
    state.startY + deltaY,
    widget.width,
    widget.definition.height,
    bounds.value.width,
    bounds.value.height,
  )
  state.currentX = position.x
  state.currentY = position.y
}

function moveDrag(event: PointerEvent) {
  const state = dragState.value
  if (!state || state.pointerId !== event.pointerId) return
  updateDragPosition(state, event.clientX, event.clientY)
}

function finishDrag(event: PointerEvent) {
  const state = dragState.value
  if (!state || state.pointerId !== event.pointerId) return
  if (
    event.currentTarget instanceof HTMLElement &&
    event.currentTarget.hasPointerCapture?.(event.pointerId)
  ) {
    event.currentTarget.releasePointerCapture(event.pointerId)
  }

  if (event.type === 'pointerup') {
    updateDragPosition(state, event.clientX, event.clientY)
  }
  if (state.moved) {
    const widget = getRenderedWidget(state.id)
    if (widget) {
      const offsetX = state.currentX - widget.dropX
      const offsetY = state.currentY - widget.dropY
      widgetStore.updateWidgetPosition(state.id, widget.dropX, widget.dropY)
      settlingState.value = { id: state.id, offsetX, offsetY }
    }
  }
  dragState.value = null
}

function finishSettling(id: string) {
  if (settlingState.value?.id === id) {
    settlingState.value = null
  }
}

function showWidgetContextMenu(id: string, event: MouseEvent) {
  event.preventDefault()
  contextMenu.value = { id, x: event.clientX, y: event.clientY }
}

function handleContextMenuSelect(key: string | number) {
  const id = contextMenu.value?.id
  if (!id) return
  if (key === 'details') openDetails(id)
  if (key === 'remove') widgetStore.removeWidget(id)
  contextMenu.value = null
}

onMounted(() => {
  updateBounds()
  if (typeof ResizeObserver !== 'undefined' && layerRef.value) {
    resizeObserver = new ResizeObserver(updateBounds)
    resizeObserver.observe(layerRef.value)
  }
  window.addEventListener('resize', updateBounds)
})

onUnmounted(() => {
  resizeObserver?.disconnect()
  window.removeEventListener('resize', updateBounds)
  dragState.value = null
  settlingState.value = null
})
</script>

<template>
  <div ref="layerRef" class="pointer-events-none absolute inset-0 z-[8]">
    <div
      v-if="dragPreview"
      data-widget-drop-preview
      class="desktop-widget-drop-preview app-radius-card pointer-events-none absolute border border-dashed border-[var(--app-primary-border-strong)] bg-[rgba(var(--app-primary-rgb),0.1)]"
      :style="{
        height: `${dragPreview.height}px`,
        left: `${dragPreview.x}px`,
        top: `${dragPreview.y}px`,
        width: `${dragPreview.width}px`,
      }"
    />

    <div
      v-for="widget in renderedWidgets"
      :key="widget.instance.id"
      :data-desktop-widget-id="widget.instance.id"
      class="desktop-widget-slot pointer-events-auto absolute"
      :class="[
        dragState?.id === widget.instance.id ? 'desktop-widget-slot--dragging' : '',
        settlingState?.id === widget.instance.id ? 'desktop-widget-slot--settling' : '',
      ]"
      :style="{
        '--widget-drag-x': `${widget.dragOffsetX}px`,
        '--widget-drag-y': `${widget.dragOffsetY}px`,
        '--widget-settle-x':
          settlingState?.id === widget.instance.id ? `${settlingState.offsetX}px` : '0px',
        '--widget-settle-y':
          settlingState?.id === widget.instance.id ? `${settlingState.offsetY}px` : '0px',
        height: `${widget.definition.height}px`,
        left: `${widget.x}px`,
        top: `${widget.y}px`,
        width: `${widget.width}px`,
      }"
      @contextmenu.stop="showWidgetContextMenu(widget.instance.id, $event)"
      @animationend.self="finishSettling(widget.instance.id)"
    >
      <!--
        The blurred surface must not sit inside a transformed ancestor: that ancestor becomes the
        backdrop root and the blur samples the widget itself instead of the wallpaper. Only the
        inner shell carries the drag/settle transform, the outer slot stays layout-only.
      -->
      <div
        class="desktop-widget-surface app-radius-card flex h-full w-full min-w-0 flex-col overflow-hidden backdrop-blur-[18px]"
        :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.68)]' : 'bg-[rgba(255,255,255,0.72)]'"
      >
        <header
          data-widget-drag-handle
          class="flex h-[42px] shrink-0 touch-none items-center justify-between border-b px-[14px] cursor-grab"
          :class="
            settingsStore.isDark
              ? 'border-[rgba(148,163,184,0.14)]'
              : 'border-[rgba(148,163,184,0.18)]'
          "
          @pointerdown="startDrag(widget.instance.id, $event)"
          @pointermove="moveDrag"
          @pointerup="finishDrag"
          @pointercancel="finishDrag"
        >
          <span class="text-[12px] font-700">{{ widget.definition.title }}</span>
          <button
            v-if="widget.definition.detailsAppId"
            type="button"
            class="webos-icon-button inline-flex h-[22px] w-[22px] items-center justify-center rounded-full border-0 bg-transparent p-0 text-inherit cursor-pointer"
            title="查看详情"
            aria-label="查看详情"
            @pointerdown.stop
            @click.stop="openDetails(widget.instance.id)"
          >
            <ExternalLink :size="14" aria-hidden="true" />
          </button>
        </header>
        <div class="min-h-0 flex-1">
          <component :is="widget.definition.component" />
        </div>
      </div>
    </div>

    <DesktopMenu
      :show="Boolean(contextMenu)"
      :x="contextMenu?.x ?? 0"
      :y="contextMenu?.y ?? 0"
      :options="contextMenuOptions"
      @close="contextMenu = null"
      @select="handleContextMenuSelect"
    />
  </div>
</template>

<style scoped>
.desktop-widget-slot {
  transition:
    left 260ms cubic-bezier(0.22, 1, 0.36, 1),
    top 260ms cubic-bezier(0.22, 1, 0.36, 1);
}

.desktop-widget-slot--dragging {
  z-index: 10;
  transform: translate3d(var(--widget-drag-x), var(--widget-drag-y), 0);
  transition: none;
  will-change: transform;
}

.desktop-widget-slot--settling {
  z-index: 10;
  animation: desktop-widget-settle 280ms cubic-bezier(0.16, 1, 0.3, 1);
  transition: none;
  will-change: transform;
}

.desktop-widget-slot--dragging [data-widget-drag-handle] {
  cursor: grabbing;
}

.desktop-widget-surface {
  transform: none;
  transform-origin: center;
  transition:
    opacity 160ms ease,
    transform 180ms cubic-bezier(0.22, 1, 0.36, 1),
    box-shadow 220ms cubic-bezier(0.22, 1, 0.36, 1);
}

.desktop-widget-slot--dragging .desktop-widget-surface {
  opacity: 0.94;
  transform: scale(1.018);
  box-shadow: 0 24px 54px rgba(15, 23, 42, 0.28);
}

/* A transformed ancestor becomes the backdrop root, so the blur is dropped while the widget is
   actually moving instead of sampling a stale snapshot every frame. */
.desktop-widget-slot--dragging .desktop-widget-surface,
.desktop-widget-slot--settling .desktop-widget-surface {
  backdrop-filter: none;
  -webkit-backdrop-filter: none;
}

.desktop-widget-drop-preview {
  z-index: 9;
  box-shadow:
    0 0 0 1px rgba(var(--app-primary-rgb), 0.08),
    0 12px 30px rgba(15, 23, 42, 0.12);
  transition:
    left 180ms cubic-bezier(0.22, 1, 0.36, 1),
    top 180ms cubic-bezier(0.22, 1, 0.36, 1),
    width 180ms cubic-bezier(0.22, 1, 0.36, 1),
    height 180ms cubic-bezier(0.22, 1, 0.36, 1);
}

@keyframes desktop-widget-settle {
  from {
    transform: translate3d(var(--widget-settle-x), var(--widget-settle-y), 0);
  }

  to {
    transform: translate3d(0, 0, 0);
  }
}

@media (prefers-reduced-motion: reduce) {
  .desktop-widget-slot,
  .desktop-widget-surface,
  .desktop-widget-drop-preview {
    transition-duration: 1ms;
  }

  .desktop-widget-slot--settling {
    animation-duration: 1ms;
  }
}
</style>

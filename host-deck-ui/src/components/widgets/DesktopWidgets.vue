<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { ExternalLink } from '@lucide/vue'
import type { DropdownOption } from 'naive-ui'
import { desktopWidgetDefinitions } from './registry'
import { useDesktopStore } from '@/stores/desktop'
import { useDesktopWidgetStore } from '@/stores/desktop-widget'
import { useSettingsStore } from '@/stores/settings'

const edgeGap = 24
const dragThreshold = 4
let detailsRequestId = 0
const desktopStore = useDesktopStore()
const widgetStore = useDesktopWidgetStore()
const settingsStore = useSettingsStore()
const layerRef = ref<HTMLElement | null>(null)
const bounds = ref({ height: 0, width: 0 })
const contextMenu = ref<{ id: string; x: number; y: number } | null>(null)
const dragState = ref<{
  currentX: number
  currentY: number
  id: string
  moved: boolean
  pointerId: number
  startPointerX: number
  startPointerY: number
  startX: number
  startY: number
} | null>(null)

const renderedWidgets = computed(() =>
  widgetStore.widgets.map((widget) => {
    const definition = desktopWidgetDefinitions[widget.type]
    const maxX = Math.max(edgeGap, bounds.value.width - definition.width - edgeGap)
    const maxY = Math.max(edgeGap, bounds.value.height - definition.height - edgeGap)
    const width =
      bounds.value.width > 0
        ? Math.min(definition.width, Math.max(0, bounds.value.width - edgeGap * 2))
        : definition.width
    const drag = dragState.value?.id === widget.id ? dragState.value : null
    const desiredX = drag?.currentX ?? widget.x ?? maxX
    const desiredY = drag?.currentY ?? widget.y ?? edgeGap
    return {
      definition,
      instance: widget,
      width,
      x: Math.min(maxX, Math.max(edgeGap, desiredX)),
      y: Math.min(maxY, Math.max(edgeGap, desiredY)),
    }
  }),
)
const contextMenuOptions = computed<DropdownOption[]>(() => {
  const widget = widgetStore.widgets.find((item) => item.id === contextMenu.value?.id)
  if (!widget) return []
  const definition = desktopWidgetDefinitions[widget.type]
  return [
    ...(definition.detailsAppId ? [{ key: 'details', label: '查看详情' }] : []),
    { key: 'remove', label: '移除小组件', props: { style: 'color: #dc2626;' } },
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

function moveDrag(event: PointerEvent) {
  const state = dragState.value
  if (!state || state.pointerId !== event.pointerId) return
  const deltaX = event.clientX - state.startPointerX
  const deltaY = event.clientY - state.startPointerY
  state.moved = state.moved || Math.hypot(deltaX, deltaY) >= dragThreshold
  if (!state.moved) return

  state.currentX = state.startX + deltaX
  state.currentY = state.startY + deltaY
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

  if (state.moved) {
    const widget = getRenderedWidget(state.id)
    if (widget) widgetStore.updateWidgetPosition(state.id, widget.x, widget.y)
  }
  dragState.value = null
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
  window.addEventListener('resize', updateBounds)
})

onUnmounted(() => {
  window.removeEventListener('resize', updateBounds)
  dragState.value = null
})
</script>

<template>
  <div ref="layerRef" class="pointer-events-none absolute inset-0 z-[8]">
    <section
      v-for="widget in renderedWidgets"
      :key="widget.instance.id"
      :data-desktop-widget-id="widget.instance.id"
      class="app-radius-card pointer-events-auto absolute flex overflow-hidden backdrop-blur-[18px]"
      :class="[
        settingsStore.isDark
          ? 'bg-[rgba(15,23,42,0.68)]'
          : 'bg-[rgba(255,255,255,0.72)]',
        dragState?.id === widget.instance.id ? 'cursor-grabbing opacity-90 transition-none' : '',
      ]"
      :style="{
        height: `${widget.definition.height}px`,
        left: `${widget.x}px`,
        top: `${widget.y}px`,
        width: `${widget.width}px`,
      }"
      @contextmenu.stop="showWidgetContextMenu(widget.instance.id, $event)"
    >
      <div class="flex min-w-0 flex-1 flex-col">
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
          <NButton
            v-if="widget.definition.detailsAppId"
            quaternary
            circle
            size="tiny"
            title="查看详情"
            aria-label="查看详情"
            @pointerdown.stop
            @click.stop="openDetails(widget.instance.id)"
          >
            <template #icon><ExternalLink :size="14" /></template>
          </NButton>
        </header>
        <div class="min-h-0 flex-1">
          <component :is="widget.definition.component" />
        </div>
      </div>
    </section>

    <NDropdown
      trigger="manual"
      placement="bottom-start"
      :show="Boolean(contextMenu)"
      :x="contextMenu?.x ?? 0"
      :y="contextMenu?.y ?? 0"
      :options="contextMenuOptions"
      @clickoutside="contextMenu = null"
      @select="handleContextMenuSelect"
    />
  </div>
</template>

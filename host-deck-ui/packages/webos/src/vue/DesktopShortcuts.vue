<script setup lang="ts">
import { ref } from 'vue'
import type { DesktopShortcut } from '../core/types'
import { snapDesktopGridPosition } from '../core/desktop-grid'
import AppIcon from './AppIcon.vue'

const props = defineProps<{ shortcuts: DesktopShortcut[] }>()
const emit = defineEmits<{ move: [id: string, x: number, y: number] }>()
const layer = ref<HTMLElement | null>(null)
let dragging:
  | { id: string; pointerId: number; clientX: number; clientY: number; x: number; y: number }
  | undefined
const position = ref<{ id: string; x: number; y: number } | null>(null)

function start(shortcut: DesktopShortcut, index: number, event: PointerEvent) {
  if (event.button !== 0) return
  dragging = {
    id: shortcut.id,
    pointerId: event.pointerId,
    clientX: event.clientX,
    clientY: event.clientY,
    x: shortcut.x ?? 20,
    y: shortcut.y ?? 20 + index * 136,
  }
  ;(event.currentTarget as HTMLElement).setPointerCapture?.(event.pointerId)
}

function move(event: PointerEvent) {
  if (!dragging || dragging.pointerId !== event.pointerId) return
  position.value = {
    id: dragging.id,
    x: dragging.x + event.clientX - dragging.clientX,
    y: dragging.y + event.clientY - dragging.clientY,
  }
}

function finish(event: PointerEvent) {
  if (!dragging || dragging.pointerId !== event.pointerId) return
  if (position.value && layer.value && event.type === 'pointerup') {
    const snapped = snapDesktopGridPosition(
      position.value.x,
      position.value.y,
      96,
      108,
      layer.value.clientWidth,
      layer.value.clientHeight,
    )
    emit('move', dragging.id, snapped.x, snapped.y)
  }
  dragging = undefined
  position.value = null
}
</script>

<template>
  <div ref="layer" class="absolute inset-0">
    <button
      v-for="(shortcut, index) in props.shortcuts"
      :key="shortcut.id"
      class="webos-shortcut absolute"
      :style="{
        left: `${position?.id === shortcut.id ? position.x : (shortcut.x ?? 20)}px`,
        top: `${position?.id === shortcut.id ? position.y : (shortcut.y ?? 20 + index * 136)}px`,
      }"
      type="button"
      @dblclick="shortcut.open"
      @keydown.enter="shortcut.open"
      @pointerdown="start(shortcut, index, $event)"
      @pointermove="move"
      @pointerup="finish"
      @pointercancel="finish"
    >
      <AppIcon :name="shortcut.icon" :size="52" />
      <span class="webos-shortcut-label">{{ shortcut.title }}</span>
    </button>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import AppIcon from '@/components/common/AppIcon.vue'
import { useDesktopStore, type WindowState } from '@/stores/desktop'

const props = defineProps<{
  window: WindowState
}>()

const desktopStore = useDesktopStore()
let isDragging = false
let isResizing = false
let dragOffsetX = 0
let dragOffsetY = 0

const windowStyle = computed(() => {
  if (props.window.isMaximized) {
    return {
      bottom: '0',
      left: 'var(--desktop-window-edge-gap)',
      top: '0',
      width: 'calc(100% - (var(--desktop-window-edge-gap) * 2))',
      zIndex: props.window.zIndex,
    }
  }

  return {
    height: `${props.window.height}px`,
    left: `${props.window.x}px`,
    top: `${props.window.y}px`,
    width: `${props.window.width}px`,
    zIndex: props.window.zIndex,
  }
})

function focusWindow() {
  desktopStore.focusWindow(props.window.id)
}

function maximizeWindow() {
  desktopStore.maximizeWindow(props.window.id)
}

function minimizeWindow() {
  desktopStore.minimizeWindow(props.window.id)
}

function closeWindow() {
  desktopStore.closeWindow(props.window.id)
}

function handleDrag(event: MouseEvent) {
  if (!isDragging || props.window.isMaximized) {
    return
  }

  const nextX = event.clientX - dragOffsetX
  const nextY = Math.max(48, event.clientY - dragOffsetY)
  desktopStore.updateWindowPosition(props.window.id, nextX, nextY)
}

function stopDrag() {
  isDragging = false
  window.removeEventListener('mousemove', handleDrag)
  window.removeEventListener('mouseup', stopDrag)
}

function startDrag(event: MouseEvent) {
  if (props.window.isMaximized) {
    return
  }

  focusWindow()
  isDragging = true
  dragOffsetX = event.clientX - props.window.x
  dragOffsetY = event.clientY - props.window.y
  window.addEventListener('mousemove', handleDrag)
  window.addEventListener('mouseup', stopDrag)
}

function handleResize(event: MouseEvent) {
  if (!isResizing || props.window.isMaximized) {
    return
  }

  const nextWidth = Math.max(320, event.clientX - props.window.x)
  const nextHeight = Math.max(240, event.clientY - props.window.y)
  desktopStore.updateWindowSize(props.window.id, nextWidth, nextHeight)
}

function stopResize() {
  isResizing = false
  window.removeEventListener('mousemove', handleResize)
  window.removeEventListener('mouseup', stopResize)
}

function startResize() {
  if (props.window.isMaximized) {
    return
  }

  focusWindow()
  isResizing = true
  window.addEventListener('mousemove', handleResize)
  window.addEventListener('mouseup', stopResize)
}
</script>

<template>
  <section class="desktop-window" :class="{ 'desktop-window-maximized': window.isMaximized }" :style="windowStyle" @mousedown="focusWindow">
    <header class="window-header" @mousedown.prevent="startDrag" @dblclick="maximizeWindow">
      <div class="window-actions" @mousedown.stop>
        <button class="window-action window-action-close" type="button" title="关闭" @click="closeWindow" />
        <button class="window-action window-action-minimize" type="button" title="最小化" @click="minimizeWindow" />
        <button
          class="window-action window-action-maximize"
          type="button"
          :title="window.isMaximized ? '还原' : '最大化'"
          @click="maximizeWindow"
        />
      </div>

      <div class="window-title">
        <AppIcon :name="window.icon" :size="16" />
        <span>{{ window.title }}</span>
      </div>

      <div class="window-header-spacer" aria-hidden="true">
        <span class="window-action window-action-placeholder" />
        <span class="window-action window-action-placeholder" />
        <span class="window-action window-action-placeholder" />
      </div>
    </header>

    <div class="window-body">
      <component :is="window.component" :window-id="window.id" v-bind="window.props" />
    </div>

    <div v-if="!window.isMaximized" class="window-resize-handle" @mousedown.prevent="startResize" />
  </section>
</template>

<style scoped>
.desktop-window {
  position: absolute;
  display: flex;
  flex-direction: column;
  min-width: 320px;
  min-height: 240px;
  border-radius: 20px;
  overflow: hidden;
  border: 1px solid rgba(148, 163, 184, 0.18);
  background: rgba(15, 23, 42, 0.72);
  backdrop-filter: blur(18px);
  box-shadow: 0 28px 80px rgba(2, 6, 23, 0.35);
}

.desktop-window-maximized {
  height: auto;
}

.window-header {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  height: 48px;
  padding: 0 14px;
  background: rgba(15, 23, 42, 0.74);
  border-bottom: 1px solid rgba(148, 163, 184, 0.14);
}

.window-title {
  position: absolute;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: 8px;
  max-width: min(65%, calc(100% - 140px));
  min-width: 0;
  color: #f8fafc;
  font-weight: 600;
  pointer-events: none;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.window-title span {
  overflow: hidden;
  text-overflow: ellipsis;
}

.window-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.window-header-spacer {
  display: flex;
  align-items: center;
  gap: 8px;
  visibility: hidden;
}

.window-action {
  position: relative;
  width: 12px;
  height: 12px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  border: none;
  border-radius: 999px;
  cursor: pointer;
  transition: filter 0.18s ease, transform 0.18s ease;
}

.window-action:hover {
  transform: scale(1.06);
  filter: brightness(0.96);
}

.window-action-close {
  background: #ff5f57;
}

.window-action-minimize {
  background: #febc2e;
}

.window-action-maximize {
  background: #28c840;
}

.window-action-placeholder {
  cursor: default;
}

.window-body {
  flex: 1;
  min-height: 0;
}

.window-resize-handle {
  position: absolute;
  right: 0;
  bottom: 0;
  width: 18px;
  height: 18px;
  cursor: nwse-resize;
}
</style>

<script setup lang="ts">
import { computed, onUnmounted, ref } from 'vue'
import AppIcon from '@/components/common/AppIcon.vue'
import { useSettingsStore } from '@/stores/settings'
import { useDesktopStore, type WindowState } from '@/stores/desktop'

const props = defineProps<{
  window: WindowState
}>()

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const isActive = computed(() => desktopStore.activeWindowId === props.window.id)
const isDragging = ref(false)
const isResizing = ref(false)
let dragOffsetX = 0
let dragOffsetY = 0

const windowStyle = computed(() => {
  if (props.window.isMaximized) {
    return {
      bottom: '0',
      left: '0',
      right: '0',
      top: '0',
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
  if (!isDragging.value || props.window.isMaximized) {
    return
  }

  const nextX = event.clientX - dragOffsetX
  const nextY = Math.max(0, event.clientY - dragOffsetY)
  desktopStore.updateWindowPosition(props.window.id, nextX, nextY)
}

function stopDrag() {
  isDragging.value = false
  window.removeEventListener('mousemove', handleDrag)
  window.removeEventListener('mouseup', stopDrag)
}

function startDrag(event: MouseEvent) {
  if (props.window.isMaximized) {
    return
  }

  focusWindow()
  isDragging.value = true
  dragOffsetX = event.clientX - props.window.x
  dragOffsetY = event.clientY - props.window.y
  window.addEventListener('mousemove', handleDrag)
  window.addEventListener('mouseup', stopDrag)
}

function handleResize(event: MouseEvent) {
  if (!isResizing.value || props.window.isMaximized) {
    return
  }

  const nextWidth = Math.max(320, event.clientX - props.window.x)
  const nextHeight = Math.max(240, event.clientY - props.window.y)
  desktopStore.updateWindowSize(props.window.id, nextWidth, nextHeight)
}

function stopResize() {
  isResizing.value = false
  window.removeEventListener('mousemove', handleResize)
  window.removeEventListener('mouseup', stopResize)
}

function startResize() {
  if (props.window.isMaximized) {
    return
  }

  focusWindow()
  isResizing.value = true
  window.addEventListener('mousemove', handleResize)
  window.addEventListener('mouseup', stopResize)
}

onUnmounted(() => {
  window.removeEventListener('mousemove', handleDrag)
  window.removeEventListener('mouseup', stopDrag)
  window.removeEventListener('mousemove', handleResize)
  window.removeEventListener('mouseup', stopResize)
})
</script>

<template>
  <section
    class="absolute flex min-h-[240px] min-w-[320px] flex-col overflow-hidden rounded-[20px] opacity-100 backdrop-blur-[18px] transition-[opacity,transform,box-shadow,border-color] duration-[240ms] ease-in-out"
    :class="[
      settingsStore.isDark
        ? 'border border-[rgba(148,163,184,0.18)] bg-[rgba(15,23,42,0.72)] shadow-[0_28px_80px_rgba(2,6,23,0.35)]'
        : 'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.76)] shadow-[0_24px_72px_rgba(148,163,184,0.24)]',
      isActive
        ? settingsStore.isDark
          ? 'border-[rgba(96,165,250,0.36)] shadow-[0_34px_96px_rgba(2,6,23,0.44)]'
          : 'border-[rgba(59,130,246,0.32)] shadow-[0_28px_84px_rgba(59,130,246,0.16)]'
        : '',
      {
        'h-auto': window.isMaximized,
        'invisible pointer-events-none opacity-0 scale-[0.92] translate-y-[14px]': window.isMinimized,
        'transition-none': isDragging || isResizing,
      },
    ]"
    :style="windowStyle"
    :aria-hidden="window.isMinimized"
    @mousedown="focusWindow"
  >
    <header
      class="relative flex h-[48px] items-center justify-between gap-[12px] border-b px-[14px]"
      :class="[
        settingsStore.isDark
          ? 'border-[rgba(148,163,184,0.14)] bg-[rgba(15,23,42,0.74)]'
          : 'border-[rgba(148,163,184,0.22)] bg-[rgba(248,250,252,0.88)]',
      ]"
      @mousedown.prevent="startDrag"
      @dblclick="maximizeWindow"
    >
      <div class="flex items-center gap-[8px]" @mousedown.stop>
        <button class="inline-flex h-[12px] w-[12px] items-center justify-center rounded-full border-0 bg-[#ff5f57] p-0 transition-[filter,transform] duration-[180ms] ease-in-out hover:scale-[1.06] hover:brightness-[0.96] cursor-pointer" type="button" title="关闭" @click="closeWindow" />
        <button class="inline-flex h-[12px] w-[12px] items-center justify-center rounded-full border-0 bg-[#febc2e] p-0 transition-[filter,transform] duration-[180ms] ease-in-out hover:scale-[1.06] hover:brightness-[0.96] cursor-pointer" type="button" title="最小化" @click="minimizeWindow" />
        <button
          class="inline-flex h-[12px] w-[12px] items-center justify-center rounded-full border-0 bg-[#28c840] p-0 transition-[filter,transform] duration-[180ms] ease-in-out hover:scale-[1.06] hover:brightness-[0.96] cursor-pointer"
          type="button"
          :title="window.isMaximized ? '还原' : '最大化'"
          @click="maximizeWindow"
        />
      </div>

      <div
        class="pointer-events-none absolute left-1/2 flex max-w-[min(65%,calc(100%_-_140px))] min-w-0 translate-x-[-50%] items-center gap-[8px] overflow-hidden text-ellipsis whitespace-nowrap font-600"
        :class="settingsStore.isDark ? 'text-[#f8fafc]' : 'text-[#0f172a]'"
      >
        <AppIcon :name="window.icon" :size="16" />
        <span class="overflow-hidden text-ellipsis">{{ window.title }}</span>
      </div>

      <div class="invisible flex items-center gap-[8px]" aria-hidden="true">
        <span class="inline-flex h-[12px] w-[12px] cursor-default items-center justify-center rounded-full border-0 p-0" />
        <span class="inline-flex h-[12px] w-[12px] cursor-default items-center justify-center rounded-full border-0 p-0" />
        <span class="inline-flex h-[12px] w-[12px] cursor-default items-center justify-center rounded-full border-0 p-0" />
      </div>
    </header>

    <div class="min-h-0 flex-1">
      <component :is="window.component" :window-id="window.id" v-bind="window.props" />
    </div>

    <div v-if="!window.isMaximized" class="absolute bottom-0 right-0 h-[18px] w-[18px] cursor-nwse-resize" @mousedown.prevent="startResize" />
  </section>
</template>

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
const isDragging = ref(false)
const isResizing = ref(false)
let dragOffsetX = 0
let dragOffsetY = 0
let resizeStartWidth = 0
let resizeStartHeight = 0
let resizeStartClientX = 0
let resizeStartClientY = 0

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
    minHeight: `${props.window.minHeight}px`,
    minWidth: `${props.window.minWidth}px`,
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
  if (!props.window.minimizable) {
    return
  }

  desktopStore.minimizeWindow(props.window.id)
}

function closeWindow() {
  void desktopStore.requestCloseWindow(props.window.id)
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

  const nextWidth = Math.max(
    props.window.minWidth,
    resizeStartWidth + event.clientX - resizeStartClientX,
  )
  const nextHeight = Math.max(
    props.window.minHeight,
    resizeStartHeight + event.clientY - resizeStartClientY,
  )
  desktopStore.updateWindowSize(props.window.id, nextWidth, nextHeight)
}

function stopResize() {
  isResizing.value = false
  window.removeEventListener('mousemove', handleResize)
  window.removeEventListener('mouseup', stopResize)
}

function startResize(event: MouseEvent) {
  if (props.window.isMaximized) {
    return
  }

  focusWindow()
  isResizing.value = true
  resizeStartWidth = props.window.width
  resizeStartHeight = props.window.height
  resizeStartClientX = event.clientX
  resizeStartClientY = event.clientY
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
    class="absolute flex flex-col overflow-hidden rounded-[20px] opacity-100 transition-[opacity,transform,box-shadow] duration-[240ms] ease-in-out"
    :class="[
      settingsStore.isDark
        ? 'bg-transparent shadow-[0_22px_48px_rgba(0,0,0,0.56),0_8px_18px_rgba(0,0,0,0.34),0_0_0_1px_rgba(255,255,255,0.08)]'
        : 'bg-transparent shadow-[0_22px_48px_rgba(15,23,42,0.20),0_8px_18px_rgba(15,23,42,0.12),0_0_0_1px_rgba(15,23,42,0.06)]',
      {
        'desktop-window--opening': !window.isClosing,
        'pointer-events-none opacity-0 scale-[0.94] translate-y-[12px]': window.isClosing,
        'h-auto rounded-none shadow-none': window.isMaximized,
        'invisible pointer-events-none opacity-0 scale-[0.92] translate-y-[14px]':
          window.isMinimized,
        'transition-none': (isDragging || isResizing) && !window.isClosing,
      },
    ]"
    :style="windowStyle"
    :aria-hidden="window.isMinimized"
    @mousedown="focusWindow"
  >
    <header
      class="relative flex h-[48px] items-center justify-between gap-[12px] border-b px-[14px] backdrop-blur-[18px] [backdrop-filter:blur(18px)_saturate(140%)]"
      :class="[
        settingsStore.isDark
          ? 'border-[rgba(148,163,184,0.14)] bg-[rgba(0,0,0,0.58)]'
          : 'border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.62)]',
      ]"
      @mousedown.prevent="startDrag"
      @dblclick="maximizeWindow"
    >
      <div class="flex items-center gap-[8px]" @mousedown.stop>
        <button
          class="inline-flex h-[12px] w-[12px] items-center justify-center rounded-full border-0 bg-[#ff5f57] p-0 transition-[filter,transform] duration-[180ms] ease-in-out hover:scale-[1.06] hover:brightness-[0.96] cursor-pointer"
          type="button"
          @click="closeWindow"
        />
        <button
          v-if="window.minimizable"
          class="inline-flex h-[12px] w-[12px] items-center justify-center rounded-full border-0 bg-[#febc2e] p-0 transition-[filter,transform] duration-[180ms] ease-in-out hover:scale-[1.06] hover:brightness-[0.96] cursor-pointer"
          type="button"
          @click="minimizeWindow"
        />
        <span
          v-else
          class="inline-flex h-[12px] w-[12px] cursor-default items-center justify-center rounded-full border-0 bg-[rgba(148,163,184,0.32)] p-0"
        />
        <button
          class="inline-flex h-[12px] w-[12px] items-center justify-center rounded-full border-0 bg-[#28c840] p-0 transition-[filter,transform] duration-[180ms] ease-in-out hover:scale-[1.06] hover:brightness-[0.96] cursor-pointer"
          type="button"
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
        <span
          class="inline-flex h-[12px] w-[12px] cursor-default items-center justify-center rounded-full border-0 p-0"
        />
        <span
          class="inline-flex h-[12px] w-[12px] cursor-default items-center justify-center rounded-full border-0 p-0"
        />
        <span
          class="inline-flex h-[12px] w-[12px] cursor-default items-center justify-center rounded-full border-0 p-0"
        />
      </div>
    </header>

    <div
      class="min-h-0 flex-1 backdrop-blur-[22px] [backdrop-filter:blur(22px)_saturate(135%)]"
      :class="settingsStore.isDark ? 'bg-[rgba(0,0,0,0.72)]' : 'bg-[rgba(255,255,255,0.76)]'"
    >
      <component :is="window.component" :window-id="window.id" v-bind="window.props" />
    </div>

    <div
      v-if="!window.isMaximized"
      class="absolute bottom-0 right-0 h-[18px] w-[18px] cursor-nwse-resize"
      @mousedown.prevent="startResize"
    />
  </section>
</template>

<style scoped>
.desktop-window--opening {
  animation: desktop-window-open 260ms cubic-bezier(0.16, 1, 0.3, 1) backwards;
}

@keyframes desktop-window-open {
  from {
    opacity: 0;
    transform: scale(0.96) translateY(12px);
  }

  to {
    opacity: 1;
    transform: scale(1) translateY(0);
  }
}
</style>

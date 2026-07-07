<script setup lang="ts">
import { computed, onUnmounted, ref } from 'vue'
import { Minus, RefreshCw, Square, X } from '@lucide/vue'
import { Renew } from '@vicons/carbon'
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
const isMacWindowControls = computed(() => settingsStore.windowControlsStyle === 'mac')

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

function refreshIframeWindow() {
  desktopStore.refreshIframeWindow(props.window.id)
}

function isWindowControlActionTarget(target: EventTarget | null) {
  return target instanceof HTMLElement && Boolean(target.closest('[data-window-control-action]'))
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
  if (isWindowControlActionTarget(event.target)) {
    return
  }

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
          'rounded-[8px]': !isMacWindowControls,
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
      <div v-if="isMacWindowControls" class="flex items-center gap-[8px]" @mousedown.stop>
        <button
          data-window-control-action
          class="inline-flex h-[12px] w-[12px] items-center justify-center rounded-full border-0 bg-[#ff5f57] p-0 transition-[filter,transform] duration-[180ms] ease-in-out hover:scale-[1.06] hover:brightness-[0.96] cursor-pointer"
          type="button"
          @click="closeWindow"
        />
        <button
          data-window-control-action
          class="inline-flex h-[12px] w-[12px] items-center justify-center rounded-full border-0 bg-[#febc2e] p-0 transition-[filter,transform] duration-[180ms] ease-in-out enabled:hover:scale-[1.06] enabled:hover:brightness-[0.96] enabled:cursor-pointer disabled:cursor-not-allowed disabled:opacity-45"
          type="button"
          :disabled="!window.minimizable"
          :title="window.minimizable ? '最小化' : '最小化不可用'"
          :aria-label="window.minimizable ? '最小化' : '最小化不可用'"
          @click="minimizeWindow"
        />
        <button
          data-window-control-action
          class="inline-flex h-[12px] w-[12px] items-center justify-center rounded-full border-0 bg-[#28c840] p-0 transition-[filter,transform] duration-[180ms] ease-in-out hover:scale-[1.06] hover:brightness-[0.96] cursor-pointer"
          type="button"
          @click="maximizeWindow"
        />
      </div>
      <div v-else class="min-w-[36px]" />

      <div
        class="pointer-events-none absolute left-1/2 flex max-w-[min(65%,calc(100%_-_140px))] min-w-0 translate-x-[-50%] items-center gap-[8px] overflow-hidden text-ellipsis whitespace-nowrap font-600"
        :class="settingsStore.isDark ? 'text-[#f8fafc]' : 'text-[#0f172a]'"
      >
        <AppIcon :name="window.icon" :size="16" />
        <span class="overflow-hidden text-ellipsis">{{ window.title }}</span>
      </div>

      <div
        class="flex min-w-[36px] items-center justify-end"
        :class="isMacWindowControls ? 'gap-[8px]' : 'gap-0 -mr-[14px]'"
        @mousedown.stop
      >
        <button
          v-if="window.appId === 'iframe-app'"
          data-window-control-action
          class="inline-flex cursor-pointer items-center justify-center border-0 bg-transparent p-0 transition-[background,transform,color] duration-[180ms] ease-in-out"
          :class="
            isMacWindowControls
              ? [
                  'h-[28px] w-[28px] rounded-full hover:scale-[1.04]',
                  settingsStore.isDark
                    ? 'bg-[rgba(148,163,184,0.12)] text-[rgba(226,232,240,0.88)] hover:bg-[rgba(148,163,184,0.2)]'
                    : 'bg-[rgba(15,23,42,0.08)] text-[rgba(15,23,42,0.74)] hover:bg-[rgba(15,23,42,0.13)]',
                ]
              : [
                  'h-[48px] w-[46px] rounded-none text-[rgba(15,23,42,0.74)] hover:bg-[rgba(15,23,42,0.08)]',
                  settingsStore.isDark
                    ? 'text-[rgba(226,232,240,0.88)] hover:bg-[rgba(148,163,184,0.14)]'
                    : 'text-[rgba(15,23,42,0.74)] hover:bg-[rgba(15,23,42,0.08)]',
                ]
          "
          type="button"
          title="刷新"
          aria-label="刷新"
          @click="refreshIframeWindow"
        >
          <NIcon :size="16">
            <component :is="isMacWindowControls ? Renew : RefreshCw" />
          </NIcon>
        </button>
        <template v-if="!isMacWindowControls">
          <button
            data-window-control-action
            class="desktop-window-win-control"
            :class="
              settingsStore.isDark
                ? 'text-[rgba(226,232,240,0.9)] enabled:hover:bg-[rgba(148,163,184,0.14)] disabled:text-[rgba(148,163,184,0.42)]'
                : 'text-[rgba(15,23,42,0.78)] enabled:hover:bg-[rgba(15,23,42,0.08)] disabled:text-[rgba(100,116,139,0.42)]'
            "
            type="button"
            :disabled="!window.minimizable"
            :title="window.minimizable ? '最小化' : '最小化不可用'"
            :aria-label="window.minimizable ? '最小化' : '最小化不可用'"
            @click="minimizeWindow"
          >
            <NIcon :size="16">
              <Minus />
            </NIcon>
          </button>
          <button
            data-window-control-action
            class="desktop-window-win-control"
            :class="
              settingsStore.isDark
                ? 'text-[rgba(226,232,240,0.9)] hover:bg-[rgba(148,163,184,0.14)]'
                : 'text-[rgba(15,23,42,0.78)] hover:bg-[rgba(15,23,42,0.08)]'
            "
            type="button"
            :title="window.isMaximized ? '还原' : '最大化'"
            :aria-label="window.isMaximized ? '还原' : '最大化'"
            @click="maximizeWindow"
          >
            <NIcon :size="14">
              <Square />
            </NIcon>
          </button>
          <button
            data-window-control-action
            class="desktop-window-win-control"
            :class="
              settingsStore.isDark
                ? 'text-[rgba(226,232,240,0.92)] hover:bg-[#c42b1c] hover:text-white'
                : 'text-[rgba(15,23,42,0.82)] hover:bg-[#c42b1c] hover:text-white'
            "
            type="button"
            title="关闭"
            aria-label="关闭"
            @click="closeWindow"
          >
            <NIcon :size="16">
              <X />
            </NIcon>
          </button>
        </template>
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

.desktop-window-win-control {
  width: 46px;
  height: 48px;
  border: 0;
  border-radius: 0;
  background: transparent;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: background-color 160ms ease, color 160ms ease;
}

.desktop-window-win-control:disabled {
  cursor: not-allowed;
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

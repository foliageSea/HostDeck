<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { createWallpaperStyle } from '@/lib/wallpapers'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import DesktopDock from '@/components/os/DesktopDock.vue'
import DesktopTopBar from '@/components/os/DesktopTopBar.vue'
import DesktopWindow from '@/components/os/DesktopWindow.vue'
import DesktopWindowSwitcher from '@/components/os/DesktopWindowSwitcher.vue'

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const switcherVisible = ref(false)
const switcherIndex = ref(0)
const switcherWindows = ref<typeof desktopStore.windows>([])

const windows = computed(() => desktopStore.windows)
const desktopWallpaperStyle = computed(() =>
  createWallpaperStyle('desktop', settingsStore.desktopWallpaper, settingsStore.isDark),
)

function selectWindow(index: number) {
  const targetWindow = switcherWindows.value[index]
  if (!targetWindow) {
    return
  }

  desktopStore.focusWindow(targetWindow.id)
  switcherVisible.value = false
}

function handleKeyDown(event: KeyboardEvent) {
  if (event.key === 'Escape' && switcherVisible.value) {
    switcherVisible.value = false
    return
  }

  const isSwitchKey = (event.ctrlKey && event.key === 'Tab') || (event.altKey && (event.key === '`' || event.key === 'q'))
  if (!isSwitchKey) {
    return
  }

  const sortedWindows = [...desktopStore.windows].sort((left, right) => right.zIndex - left.zIndex)
  if (sortedWindows.length < 2) {
    return
  }

  event.preventDefault()
  event.stopPropagation()

  if (!switcherVisible.value) {
    switcherWindows.value = sortedWindows
    switcherVisible.value = true
    switcherIndex.value = event.shiftKey ? sortedWindows.length - 1 : 1
    return
  }

  if (event.shiftKey) {
    switcherIndex.value = (switcherIndex.value - 1 + switcherWindows.value.length) % switcherWindows.value.length
    return
  }

  switcherIndex.value = (switcherIndex.value + 1) % switcherWindows.value.length
}

function handleKeyUp(event: KeyboardEvent) {
  if ((event.key === 'Control' || event.key === 'Alt') && switcherVisible.value) {
    selectWindow(switcherIndex.value)
  }
}

onMounted(() => {
  window.addEventListener('keydown', handleKeyDown, true)
  window.addEventListener('keyup', handleKeyUp, true)
})

onUnmounted(() => {
  window.removeEventListener('keydown', handleKeyDown, true)
  window.removeEventListener('keyup', handleKeyUp, true)
})
</script>

<template>
  <div
    class="relative min-h-screen overflow-hidden [--desktop-topbar-height:48px] [--desktop-window-edge-gap:16px] [--desktop-dock-bottom-gap:24px] [--desktop-dock-height:72px] [--desktop-dock-safe-area:calc(var(--desktop-dock-bottom-gap)_+_var(--desktop-dock-height)_+_16px)]">
    <div class="absolute inset-0 bg-cover bg-center bg-no-repeat" :style="desktopWallpaperStyle" />
    <div class="absolute inset-0 [backdrop-filter:saturate(108%)]" />

    <DesktopTopBar />

    <main class="absolute [inset:var(--desktop-topbar-height)_0_var(--desktop-dock-safe-area)]">
      <TransitionGroup name="desktop-window-anim" tag="div" class="relative h-full w-full">
        <DesktopWindow v-for="window in windows" :key="window.id" :window="window" />
      </TransitionGroup>
    </main>

    <DesktopDock />

    <DesktopWindowSwitcher v-if="switcherVisible" :windows="switcherWindows" :selected-index="switcherIndex"
      @select="selectWindow" />

    <!-- <div
      class="desktop-status-card absolute bottom-[var(--desktop-dock-safe-area)] right-[24px] z-[15] w-[280px] rounded-[18px] p-[16px] backdrop-blur-[16px]"
      :class="[
        settingsStore.isDark
          ? 'border border-[rgba(148,163,184,0.18)] bg-[rgba(15,23,42,0.5)]'
          : 'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.62)]',
      ]"
    >
      <div class="text-[0.82rem]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.68)]' : 'text-[rgba(71,85,105,0.82)]'">当前连接</div>
      <div class="mt-[6px] text-[1.1rem] font-600" :class="settingsStore.isDark ? 'text-[#f8fafc]' : 'text-[#0f172a]'">{{ sshStore.username }}@{{ sshStore.host }}</div>
      <div class="mt-[8px] text-[0.86rem]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.7)]' : 'text-[rgba(51,65,85,0.8)]'">当前会话已接入桌面环境，可继续打开监控、终端和文件等工作窗口。</div>
    </div> -->
  </div>
</template>

<style scoped>
.desktop-window-anim-enter-active,
.desktop-window-anim-leave-active {
  transition: all 0.28s cubic-bezier(0.16, 1, 0.3, 1);
}

.desktop-window-anim-enter-from,
.desktop-window-anim-leave-to {
  opacity: 0;
  transform: scale(0.96) translateY(10px);
}

@media (max-width: 768px) {
  .desktop-status-card {
    left: 16px;
    right: 16px;
    bottom: calc(var(--desktop-dock-safe-area) - 18px);
    width: auto;
  }
}
</style>

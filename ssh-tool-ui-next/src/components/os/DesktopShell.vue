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
  <div class="desktop-shell" :class="{ 'desktop-shell-light': !settingsStore.isDark }">
    <div class="desktop-wallpaper" :style="desktopWallpaperStyle" />
    <div class="desktop-noise" />

    <DesktopTopBar />

    <main class="desktop-main">
      <TransitionGroup name="desktop-window-anim" tag="div" class="desktop-window-layer">
        <DesktopWindow v-for="window in windows" :key="window.id" :window="window" />
      </TransitionGroup>
    </main>

    <DesktopDock />

    <DesktopWindowSwitcher
      v-if="switcherVisible"
      :windows="switcherWindows"
      :selected-index="switcherIndex"
      @select="selectWindow"
    />

    <div class="desktop-status-card">
      <div class="desktop-status-title">当前连接</div>
      <div class="desktop-status-value">{{ sshStore.username }}@{{ sshStore.host }}</div>
      <div class="desktop-status-meta">当前会话已接入桌面环境，可继续打开监控、终端和文件等工作窗口。</div>
    </div>
  </div>
</template>

<style scoped>
.desktop-shell {
  position: relative;
  min-height: 100vh;
  overflow: hidden;
  --desktop-topbar-height: 48px;
  --desktop-topbar-offset: 8px;
  --desktop-window-edge-gap: 16px;
  --desktop-dock-bottom-gap: 24px;
  --desktop-dock-height: 64px;
  --desktop-dock-safe-area: calc(var(--desktop-dock-bottom-gap) + var(--desktop-dock-height) + 16px);
}

.desktop-wallpaper {
  position: absolute;
  inset: 0;
  background-position: center;
  background-repeat: no-repeat;
  background-size: cover;
}

.desktop-noise {
  position: absolute;
  inset: 0;
  backdrop-filter: saturate(108%);
}

.desktop-main {
  position: absolute;
  inset: calc(var(--desktop-topbar-height) + var(--desktop-topbar-offset)) 0 var(--desktop-dock-safe-area);
}

.desktop-window-layer {
  position: relative;
  width: 100%;
  height: 100%;
}

.desktop-window-anim-enter-active,
.desktop-window-anim-leave-active {
  transition: all 0.28s cubic-bezier(0.16, 1, 0.3, 1);
}

.desktop-window-anim-enter-from,
.desktop-window-anim-leave-to {
  opacity: 0;
  transform: scale(0.96) translateY(10px);
}

.desktop-status-card {
  position: absolute;
  right: 24px;
  bottom: var(--desktop-dock-safe-area);
  width: 280px;
  padding: 16px;
  border-radius: 18px;
  background: rgba(15, 23, 42, 0.5);
  border: 1px solid rgba(148, 163, 184, 0.18);
  backdrop-filter: blur(16px);
  z-index: 15;
}

.desktop-status-title {
  font-size: 0.82rem;
  color: rgba(226, 232, 240, 0.68);
}

.desktop-status-value {
  margin-top: 6px;
  font-size: 1.1rem;
  font-weight: 600;
  color: #f8fafc;
}

.desktop-status-meta {
  margin-top: 8px;
  font-size: 0.86rem;
  color: rgba(226, 232, 240, 0.7);
}

.desktop-shell-light .desktop-status-card {
  background: rgba(255, 255, 255, 0.62);
  border-color: rgba(148, 163, 184, 0.22);
}

.desktop-shell-light .desktop-status-title {
  color: rgba(71, 85, 105, 0.82);
}

.desktop-shell-light .desktop-status-value {
  color: #0f172a;
}

.desktop-shell-light .desktop-status-meta {
  color: rgba(51, 65, 85, 0.8);
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

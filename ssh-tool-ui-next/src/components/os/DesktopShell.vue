<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
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

const windows = computed(() => desktopStore.windows.filter((window) => !window.isMinimized))

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
  if (desktopStore.windows.length === 0) {
    desktopStore.openWindow('dashboard')
  }

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
    <div class="desktop-wallpaper" />
    <div class="desktop-noise" />

    <DesktopTopBar />

    <main class="desktop-main">
      <DesktopWindow v-for="window in windows" :key="window.id" :window="window" />
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
}

.desktop-wallpaper {
  position: absolute;
  inset: 0;
  background:
    radial-gradient(circle at 15% 18%, rgba(14, 165, 233, 0.18), transparent 24%),
    radial-gradient(circle at 85% 15%, rgba(168, 85, 247, 0.18), transparent 18%),
    radial-gradient(circle at 50% 85%, rgba(59, 130, 246, 0.12), transparent 24%),
    linear-gradient(160deg, #0f172a 0%, #111827 50%, #020617 100%);
}

.desktop-shell-light .desktop-wallpaper {
  background:
    radial-gradient(circle at 15% 18%, rgba(59, 130, 246, 0.16), transparent 24%),
    radial-gradient(circle at 85% 15%, rgba(217, 70, 239, 0.14), transparent 18%),
    linear-gradient(160deg, #dbeafe 0%, #e2e8f0 50%, #cbd5e1 100%);
}

.desktop-noise {
  position: absolute;
  inset: 0;
  backdrop-filter: saturate(108%);
}

.desktop-main {
  position: absolute;
  inset: 56px 0 110px;
}

.desktop-status-card {
  position: absolute;
  right: 24px;
  bottom: 110px;
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

@media (max-width: 768px) {
  .desktop-status-card {
    left: 16px;
    right: 16px;
    bottom: 92px;
    width: auto;
  }
}
</style>

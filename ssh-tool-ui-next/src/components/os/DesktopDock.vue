<script setup lang="ts">
import { computed, ref } from 'vue'
import { onClickOutside } from '@vueuse/core'
import AppIcon from '@/components/common/AppIcon.vue'
import { useDesktopStore, type AppConfig } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import type { DesktopAppId } from '@/types/desktop'

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const selectorTarget = ref<HTMLElement | null>(null)
const selectorAppId = ref<DesktopAppId | null>(null)
const bouncingAppId = ref<DesktopAppId | null>(null)

const dockApps = computed<AppConfig[]>(() => Object.values(desktopStore.apps).filter((app) => !app.hide))

onClickOutside(selectorTarget, () => {
  selectorAppId.value = null
})

function getAppWindows(appId: DesktopAppId) {
  return desktopStore.windows.filter((window) => window.appId === appId)
}

function isAppOpen(appId: DesktopAppId) {
  return getAppWindows(appId).length > 0
}

function handleOpen(appId: DesktopAppId) {
  bouncingAppId.value = appId
  window.setTimeout(() => {
    if (bouncingAppId.value === appId) {
      bouncingAppId.value = null
    }
  }, 380)

  if (selectorAppId.value === appId) {
    selectorAppId.value = null
    return
  }

  const windows = getAppWindows(appId)
  if (windows.length === 0) {
    desktopStore.openWindow(appId)
    return
  }

  if (windows.length === 1 && windows[0]) {
    desktopStore.restoreWindow(windows[0].id)
    return
  }

  selectorAppId.value = appId
}

function activateWindow(windowId: string) {
  desktopStore.restoreWindow(windowId)
  selectorAppId.value = null
}

function openNewWindow(appId: DesktopAppId) {
  desktopStore.openWindow(appId)
  selectorAppId.value = null
}

function closeAppWindows(appId: DesktopAppId) {
  desktopStore.closeAppWindows(appId)
  selectorAppId.value = null
}
</script>

<template>
  <footer ref="selectorTarget" class="desktop-dock" :class="{ 'desktop-dock-light': !settingsStore.isDark }">
    <div v-for="app in dockApps" :key="app.id" class="dock-entry">
      <button
        class="dock-item"
        :class="{
          'dock-item-open': isAppOpen(app.id),
          'dock-item-bounce': bouncingAppId === app.id,
        }"
        type="button"
        @click="handleOpen(app.id)"
      >
        <AppIcon :name="app.icon" :size="20" />
        <span>{{ app.title }}</span>
      </button>

      <div v-if="selectorAppId === app.id" class="dock-selector">
        <div class="dock-selector-title">选择窗口</div>
        <button
          v-for="window in getAppWindows(app.id)"
          :key="window.id"
          type="button"
          class="dock-selector-item"
          @click="activateWindow(window.id)"
        >
          <span>{{ window.title }}</span>
          <span v-if="desktopStore.activeWindowId === window.id" class="dock-selector-indicator" />
        </button>
        <div class="dock-selector-actions">
          <NButton secondary size="small" @click="openNewWindow(app.id)">新建窗口</NButton>
          <NButton tertiary size="small" type="error" @click="closeAppWindows(app.id)">关闭全部</NButton>
        </div>
      </div>
    </div>
  </footer>
</template>

<style scoped>
.desktop-dock {
  position: absolute;
  left: 50%;
  bottom: 24px;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px;
  border-radius: 22px;
  background: rgba(15, 23, 42, 0.56);
  border: 1px solid rgba(148, 163, 184, 0.16);
  backdrop-filter: blur(16px);
  z-index: 20;
}

.dock-entry {
  position: relative;
}

.dock-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 14px;
  border-radius: 16px;
  border: none;
  color: #e2e8f0;
  background: rgba(30, 41, 59, 0.72);
  cursor: pointer;
  transition: transform 0.18s ease, background-color 0.18s ease;
}

.dock-item:hover,
.dock-item-open {
  transform: translateY(-2px);
  background: rgba(51, 65, 85, 0.92);
}

.dock-item-bounce {
  animation: dock-bounce 0.38s ease;
}

.dock-selector {
  position: absolute;
  left: 50%;
  bottom: calc(100% + 12px);
  transform: translateX(-50%);
  width: 220px;
  padding: 10px;
  border-radius: 16px;
  background: rgba(15, 23, 42, 0.9);
  border: 1px solid rgba(148, 163, 184, 0.16);
  box-shadow: 0 24px 70px rgba(2, 6, 23, 0.35);
}

.dock-selector-title {
  margin-bottom: 8px;
  font-size: 0.78rem;
  color: rgba(226, 232, 240, 0.62);
}

.dock-selector-item {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 6px;
  padding: 8px 10px;
  border: none;
  border-radius: 12px;
  background: rgba(30, 41, 59, 0.7);
  color: #e2e8f0;
  cursor: pointer;
}

.dock-selector-item:hover {
  background: rgba(51, 65, 85, 0.92);
}

.dock-selector-indicator {
  width: 8px;
  height: 8px;
  border-radius: 999px;
  background: #60a5fa;
}

.dock-selector-actions {
  display: flex;
  gap: 8px;
  margin-top: 8px;
}

@keyframes dock-bounce {
  0% {
    transform: translateY(0);
  }
  40% {
    transform: translateY(-6px);
  }
  100% {
    transform: translateY(0);
  }
}

@media (max-width: 768px) {
  .desktop-dock {
    width: calc(100% - 20px);
    justify-content: space-between;
    gap: 8px;
  }

  .dock-item {
    flex: 1;
    justify-content: center;
    padding: 10px;
  }

  .dock-item span {
    display: none;
  }
}

.desktop-dock-light {
  background: rgba(255, 255, 255, 0.66);
  border-color: rgba(148, 163, 184, 0.22);
}

.desktop-dock-light .dock-item {
  color: #1e293b;
  background: rgba(241, 245, 249, 0.88);
}

.desktop-dock-light .dock-item:hover,
.desktop-dock-light .dock-item-open {
  background: rgba(226, 232, 240, 0.96);
}

.desktop-dock-light .dock-selector {
  background: rgba(255, 255, 255, 0.94);
  border-color: rgba(148, 163, 184, 0.22);
  box-shadow: 0 24px 70px rgba(148, 163, 184, 0.22);
}

.desktop-dock-light .dock-selector-title {
  color: rgba(71, 85, 105, 0.84);
}

.desktop-dock-light .dock-selector-item {
  background: rgba(241, 245, 249, 0.92);
  color: #1e293b;
}

.desktop-dock-light .dock-selector-item:hover {
  background: rgba(226, 232, 240, 0.96);
}
</style>

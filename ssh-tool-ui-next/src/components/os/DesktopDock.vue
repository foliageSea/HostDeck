<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import AppIcon from '@/components/common/AppIcon.vue'
import { useDesktopStore, type AppConfig } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import type { DesktopAppId } from '@/types/desktop'

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const selectorTarget = ref<HTMLElement | null>(null)
const selectorPanel = ref<HTMLElement | null>(null)
const selectorAppId = ref<DesktopAppId | null>(null)
const bouncingAppId = ref<DesktopAppId | null>(null)
const selectorPosition = ref<{
  x: number
  y: number
} | null>(null)
const contextMenu = ref<{
  appId: DesktopAppId
  x: number
  y: number
} | null>(null)
const contextMenuOptions = computed(() => {
  const appId = contextMenu.value?.appId
  if (!appId) {
    return []
  }

  const hasWindows = getAppWindows(appId).length > 0
  return [
    { key: 'new', label: '新建窗口' },
    ...(hasWindows ? [{ key: 'close-all', label: '关闭全部窗口', props: { style: 'color: #dc2626;' } }] : []),
  ]
})

const dockApps = computed<AppConfig[]>(() => Object.values(desktopStore.apps).filter((app) => !app.hide))
const selectorWindows = computed(() => {
  const appId = selectorAppId.value
  return appId ? getAppWindows(appId) : []
})

function closeSelector() {
  selectorAppId.value = null
  selectorPosition.value = null
}

function handleGlobalPointerDown(event: PointerEvent) {
  const target = event.target
  if (!(target instanceof Node)) {
    return
  }

  if (selectorTarget.value?.contains(target) || selectorPanel.value?.contains(target)) {
    return
  }

  closeSelector()
}

onMounted(() => {
  window.addEventListener('pointerdown', handleGlobalPointerDown, true)
})

onUnmounted(() => {
  window.removeEventListener('pointerdown', handleGlobalPointerDown, true)
})

function getAppWindows(appId: DesktopAppId) {
  return desktopStore.windows.filter((window) => window.appId === appId)
}

function isAppOpen(appId: DesktopAppId) {
  return getAppWindows(appId).length > 0
}

function handleOpen(event: MouseEvent, appId: DesktopAppId) {
  contextMenu.value = null
  bouncingAppId.value = appId
  window.setTimeout(() => {
    if (bouncingAppId.value === appId) {
      bouncingAppId.value = null
    }
  }, 380)

  if (selectorAppId.value === appId) {
    closeSelector()
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

  const currentTarget = event.currentTarget
  if (currentTarget instanceof HTMLElement) {
    const rect = currentTarget.getBoundingClientRect()
    selectorPosition.value = {
      x: rect.left + rect.width / 2,
      y: rect.top - 12,
    }
  }

  selectorAppId.value = appId
}

function handleContextMenu(event: MouseEvent, appId: DesktopAppId) {
  event.preventDefault()
  closeSelector()
  contextMenu.value = {
    appId,
    x: event.clientX,
    y: event.clientY,
  }
}

function handleTriggerKeydown(event: KeyboardEvent, appId: DesktopAppId) {
  if (event.key !== 'ContextMenu' && !(event.shiftKey && event.key === 'F10')) {
    return
  }

  event.preventDefault()
  const target = event.currentTarget
  if (!(target instanceof HTMLElement)) {
    return
  }

  const rect = target.getBoundingClientRect()
  closeSelector()
  contextMenu.value = {
    appId,
    x: rect.left + rect.width / 2,
    y: rect.top,
  }
}

function activateWindow(windowId: string) {
  desktopStore.restoreWindow(windowId)
  closeSelector()
  contextMenu.value = null
}

function openNewWindow(appId: DesktopAppId) {
  desktopStore.openWindow(appId)
  closeSelector()
  contextMenu.value = null
}

function closeAppWindows(appId: DesktopAppId) {
  desktopStore.closeAppWindows(appId)
  closeSelector()
  contextMenu.value = null
}

function closeContextMenu() {
  contextMenu.value = null
}

function handleContextMenuSelect(key: string | number) {
  const appId = contextMenu.value?.appId
  if (!appId) {
    return
  }

  if (key === 'new') {
    openNewWindow(appId)
    return
  }

  if (key === 'close-all') {
    closeAppWindows(appId)
    return
  }

  closeContextMenu()
}
</script>

<template>
  <footer ref="selectorTarget" class="desktop-dock" :class="{ 'desktop-dock-light': !settingsStore.isDark }"
    @contextmenu.prevent>
    <div v-for="app in dockApps" :key="app.id" class="dock-entry">
      <button class="dock-item" :class="{
        'dock-item-open': isAppOpen(app.id),
        'dock-item-bounce': bouncingAppId === app.id,
      }" type="button" @click="handleOpen($event, app.id)" @contextmenu="handleContextMenu($event, app.id)"
        @keydown="handleTriggerKeydown($event, app.id)">
        <AppIcon :name="app.icon" :size="20" />
        <span>{{ app.title }}</span>
        <span v-if="isAppOpen(app.id)" class="dock-item-indicator" aria-hidden="true" />
      </button>

    </div>

    <Teleport to="body">
      <div v-if="selectorAppId && selectorPosition" ref="selectorPanel" class="dock-selector" :style="{
        left: `${selectorPosition.x}px`,
        top: `${selectorPosition.y}px`,
      }">
        <div class="dock-selector-title">选择窗口</div>
        <button v-for="window in selectorWindows" :key="window.id" type="button" class="dock-selector-item"
          @click="activateWindow(window.id)">
          <span>{{ window.title }}</span>
          <span v-if="desktopStore.activeWindowId === window.id" class="dock-selector-indicator" />
        </button>
        <div class="dock-selector-actions">
          <NButton secondary size="small" @click="openNewWindow(selectorAppId)">新建窗口</NButton>
          <NButton tertiary size="small" type="error" @click="closeAppWindows(selectorAppId)">关闭全部</NButton>
        </div>
      </div>
    </Teleport>

    <NDropdown placement="bottom-start" trigger="manual" :show="Boolean(contextMenu)" :x="contextMenu?.x ?? 0"
      :y="contextMenu?.y ?? 0" :options="contextMenuOptions" @clickoutside="closeContextMenu"
      @select="handleContextMenuSelect" />
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
  position: relative;
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

.dock-item-indicator {
  position: absolute;
  left: 50%;
  bottom: 4px;
  width: 6px;
  height: 6px;
  border-radius: 999px;
  background: #60a5fa;
  transform: translateX(-50%);
}

.dock-selector {
  position: fixed;
  transform: translate(-50%, -100%);
  width: 220px;
  padding: 10px;
  border-radius: 16px;
  background: rgba(15, 23, 42, 0.9);
  border: 1px solid rgba(148, 163, 184, 0.16);
  box-shadow: 0 24px 70px rgba(2, 6, 23, 0.35);
  z-index: 9999;
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

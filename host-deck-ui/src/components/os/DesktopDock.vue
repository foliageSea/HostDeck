<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { LayoutGrid } from '@lucide/vue'
import AppIcon from '@/components/common/AppIcon.vue'
import { useDesktopStore, type AppConfig } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import type { DesktopAppId } from '@/types/desktop'

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const emit = defineEmits<{
  openLaunchpad: []
}>()
const selectorTarget = ref<HTMLElement | null>(null)
const selectorPanel = ref<HTMLElement | null>(null)
const selectorAppId = ref<DesktopAppId | null>(null)
const bouncingAppId = ref<DesktopAppId | null>(null)
const hoveredDockIndex = ref<number | null>(null)
const draggedAppId = ref<DesktopAppId | null>(null)
const dragOverAppId = ref<DesktopAppId | null>(null)
const selectorPosition = ref<{
  x: number
  y: number
} | null>(null)
const contextMenu = ref<{
  appId: DesktopAppId
  x: number
  y: number
} | null>(null)
const dockIconColors: Partial<Record<DesktopAppId, string>> = {
  dashboard: '#38bdf8',
  docker: '#0ea5e9',
  files: '#f59e0b',
  opencode: '#a855f7',
  'port-forward': '#06b6d4',
  processes: '#22c55e',
  'runtime-sessions': '#22c55e',
  settings: '#94a3b8',
  terminal: '#34d399',
}
const contextMenuOptions = computed(() => {
  const appId = contextMenu.value?.appId
  if (!appId) {
    return []
  }

  const hasWindows = getAppWindows(appId).length > 0
  const appIndex = desktopStore.dockAppIds.indexOf(appId)
  return [
    { key: 'new', label: '新建窗口', disabled: !desktopStore.canOpenWindow(appId) },
    { key: 'move-left', label: '向左移动', disabled: appIndex <= 0 },
    {
      key: 'move-right',
      label: '向右移动',
      disabled: appIndex === -1 || appIndex >= desktopStore.dockAppIds.length - 1,
    },
    { key: 'unpin', label: '从 Dock 移除' },
    ...(hasWindows
      ? [{ key: 'close-all', label: '关闭全部窗口', props: { style: 'color: #dc2626;' } }]
      : []),
  ]
})

const dockApps = computed<AppConfig[]>(() =>
  desktopStore.dockAppIds
    .map((appId) => desktopStore.apps[appId])
    .filter((app): app is AppConfig => Boolean(app?.showInLaunchpad)),
)
const isDockExpanded = computed(
  () => !settingsStore.dockAutoHide || Boolean(selectorAppId.value || contextMenu.value),
)
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

function getDockIconColor(appId: DesktopAppId) {
  return dockIconColors[appId] ?? 'currentColor'
}

function getDockItemStyle(index: number, appId: DesktopAppId) {
  const hoveredIndex = hoveredDockIndex.value
  const isOpen = isAppOpen(appId)

  if (hoveredIndex === null) {
    return {
      '--dock-scale': '1',
      '--dock-lift': isOpen ? '-2px' : '0px',
      '--dock-spread': '0px',
    }
  }

  const distance = Math.abs(index - hoveredIndex)
  const scale = distance === 0 ? 1.34 : distance === 1 ? 1.16 : distance === 2 ? 1.06 : 1
  const lift = distance === 0 ? -10 : distance === 1 ? -5 : distance === 2 ? -2 : isOpen ? -2 : 0
  const spread = distance === 0 ? 9 : distance === 1 ? 3 : 0

  return {
    '--dock-scale': String(scale),
    '--dock-lift': `${lift}px`,
    '--dock-spread': `${spread}px`,
  }
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

  if (key === 'unpin') {
    desktopStore.unpinAppFromDock(appId)
    closeContextMenu()
    return
  }

  if (key === 'move-left' || key === 'move-right') {
    const appIndex = desktopStore.dockAppIds.indexOf(appId)
    const offset = key === 'move-left' ? -1 : 1
    const targetAppId = desktopStore.dockAppIds[appIndex + offset]
    if (targetAppId) {
      desktopStore.moveDockApp(appId, targetAppId)
    }
    closeContextMenu()
    return
  }

  closeContextMenu()
}

function handleDragStart(event: DragEvent, appId: DesktopAppId) {
  draggedAppId.value = appId
  event.dataTransfer?.setData('text/plain', appId)
  if (event.dataTransfer) {
    event.dataTransfer.effectAllowed = 'move'
  }
  closeSelector()
  contextMenu.value = null
}

function handleDragOver(event: DragEvent, appId: DesktopAppId) {
  if (!draggedAppId.value || draggedAppId.value === appId) {
    return
  }

  event.preventDefault()
  dragOverAppId.value = appId
  if (event.dataTransfer) {
    event.dataTransfer.dropEffect = 'move'
  }
}

function handleDrop(event: DragEvent, targetAppId: DesktopAppId) {
  event.preventDefault()
  const appId = draggedAppId.value
  if (appId) {
    desktopStore.moveDockApp(appId, targetAppId)
  }
  handleDragEnd()
}

function handleDragEnd() {
  draggedAppId.value = null
  dragOverAppId.value = null
}

function openLaunchpad() {
  closeSelector()
  contextMenu.value = null
  emit('openLaunchpad')
}
</script>

<template>
  <div class="dock-hover-zone absolute inset-x-0 bottom-0 z-20 h-[12px]">
    <footer
      ref="selectorTarget"
      class="app-radius-card desktop-dock absolute bottom-0 left-1/2 flex translate-x-[-50%] items-center gap-[12px] rounded-[24px] p-[10px] backdrop-blur-[16px]"
      :class="[
        { 'dock-auto-hide': settingsStore.dockAutoHide, 'dock-expanded': isDockExpanded },
        settingsStore.isDark
          ? 'border border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.3)]'
          : 'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.36)]',
      ]"
      @contextmenu.prevent
    >
      <NTooltip>
        <template #trigger>
          <button
            type="button"
            class="app-radius-surface launchpad-trigger flex h-[52px] w-[52px] shrink-0 items-center justify-center rounded-[16px] border-0 transition-[transform,background-color] duration-[180ms] cursor-pointer"
            :class="
              settingsStore.isDark
                ? 'bg-[#000] text-[#e2e8f0] hover:bg-[#000]'
                : 'bg-[#fff] text-[#334155] hover:bg-[#fff]'
            "
            aria-label="打开启动台"
            @click="openLaunchpad"
          >
            <LayoutGrid :size="25" />
          </button>
        </template>
        启动台
      </NTooltip>

      <span class="h-[34px] w-px shrink-0 bg-[rgba(148,163,184,0.3)]" aria-hidden="true" />

      <TransitionGroup name="dock-app" tag="div" class="flex items-center gap-[12px]">
        <div
          v-for="(app, index) in dockApps"
          :key="app.id"
          class="dock-entry relative"
          :class="{
            'dock-entry-dragging': draggedAppId === app.id,
            'dock-entry-drag-over': dragOverAppId === app.id,
          }"
          draggable="true"
          @mouseenter="hoveredDockIndex = index"
          @mouseleave="hoveredDockIndex = null"
          @dragstart="handleDragStart($event, app.id)"
          @dragover="handleDragOver($event, app.id)"
          @dragleave="dragOverAppId = null"
          @drop="handleDrop($event, app.id)"
          @dragend="handleDragEnd"
        >
          <NTooltip>
            <template #trigger>
              <div
                class="app-radius-surface dock-item relative flex h-[52px] w-[52px] items-center justify-center rounded-[16px] border-0 p-0 transition-[transform,background-color,margin] duration-[180ms] ease-out cursor-pointer"
                :class="[
                  settingsStore.isDark
                    ? 'bg-[#000] text-[#e2e8f0]'
                    : 'bg-[#fff] text-[#1e293b]',
                  isAppOpen(app.id)
                    ? settingsStore.isDark
                      ? 'bg-[#000]'
                      : 'bg-[#fff]'
                    : '',
                  { 'dock-item-bounce': bouncingAppId === app.id },
                ]"
                :style="getDockItemStyle(index, app.id)"
                type="button"
                :aria-label="app.title"
                @click="handleOpen($event, app.id)"
                @contextmenu="handleContextMenu($event, app.id)"
                @keydown="handleTriggerKeydown($event, app.id)"
              >
                <AppIcon :color="getDockIconColor(app.id)" :name="app.icon" :size="24" />
                <span
                  v-if="isAppOpen(app.id)"
                  class="absolute bottom-[4px] left-1/2 h-[6px] w-[6px] translate-x-[-50%] rounded-full bg-[var(--app-primary-color)]"
                  aria-hidden="true"
                />
              </div>
            </template>
            {{ app.title }}
          </NTooltip>
        </div>
      </TransitionGroup>

      <Teleport to="body">
        <div
          v-if="selectorAppId && selectorPosition"
          ref="selectorPanel"
          class="app-radius-surface fixed z-[9999] w-[220px] translate-x-[-50%] translate-y-[-100%] rounded-[16px] p-[10px]"
          :class="[
            settingsStore.isDark
              ? 'border border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.9)] shadow-[0_24px_70px_rgba(2,6,23,0.35)]'
              : 'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.94)] shadow-[0_24px_70px_rgba(148,163,184,0.22)]',
          ]"
          :style="{
            left: `${selectorPosition.x}px`,
            top: `${selectorPosition.y}px`,
          }"
        >
          <div
            class="mb-[8px] text-[0.78rem]"
            :class="
              settingsStore.isDark ? 'text-[rgba(226,232,240,0.62)]' : 'text-[rgba(71,85,105,0.84)]'
            "
          >
            选择窗口
          </div>
          <button
            v-for="window in selectorWindows"
            :key="window.id"
            type="button"
            class="app-radius-item mb-[6px] flex w-full items-center justify-between rounded-[12px] border-0 px-[10px] py-[8px] cursor-pointer"
            :class="[
              settingsStore.isDark
                ? 'bg-[rgba(30,41,59,0.7)] text-[#e2e8f0] hover:bg-[rgba(51,65,85,0.92)]'
                : 'bg-[rgba(241,245,249,0.92)] text-[#1e293b] hover:bg-[rgba(226,232,240,0.96)]',
            ]"
            @click="activateWindow(window.id)"
          >
            <span>{{ window.title }}</span>
            <span
              v-if="desktopStore.activeWindowId === window.id"
              class="h-[8px] w-[8px] rounded-full bg-[var(--app-primary-color)]"
            />
          </button>
          <div class="mt-[8px] flex gap-[8px]">
            <NButton
              secondary
              size="small"
              :disabled="!desktopStore.canOpenWindow(selectorAppId)"
              @click="openNewWindow(selectorAppId)"
              >新建窗口</NButton
            >
            <NButton tertiary size="small" type="error" @click="closeAppWindows(selectorAppId)"
              >关闭全部</NButton
            >
          </div>
        </div>
      </Teleport>

      <NDropdown
        placement="bottom-start"
        trigger="manual"
        :show="Boolean(contextMenu)"
        :x="contextMenu?.x ?? 0"
        :y="contextMenu?.y ?? 0"
        :options="contextMenuOptions"
        @clickoutside="closeContextMenu"
        @select="handleContextMenuSelect"
      />
    </footer>
  </div>
</template>

<style scoped>
.dock-entry {
  display: flex;
  align-items: flex-end;
}

.dock-entry-dragging {
  opacity: 0.45;
}

.dock-entry-drag-over::before {
  position: absolute;
  inset: 3px;
  border: 2px solid var(--app-primary-color);
  border-radius: 18px;
  pointer-events: none;
  content: '';
}

.dock-app-enter-active,
.dock-app-leave-active,
.dock-app-move {
  transition:
    opacity 220ms ease,
    transform 260ms cubic-bezier(0.16, 1, 0.3, 1);
}

.dock-app-enter-from,
.dock-app-leave-to {
  opacity: 0;
  transform: translateY(14px) scale(0.82);
}

.dock-app-leave-active {
  position: absolute;
}

.desktop-dock {
  transform: translateX(-50%);
  transition: transform 220ms ease-out;
}

.dock-item {
  margin-inline: var(--dock-spread, 0);
  transform: translateY(var(--dock-lift, 0)) scale(var(--dock-scale, 1));
  transform-origin: center bottom;
  will-change: transform;
}

.dock-item-bounce {
  animation: dock-bounce 0.38s ease;
}

@keyframes dock-bounce {
  0% {
    transform: translateY(var(--dock-lift, 0)) scale(var(--dock-scale, 1));
  }

  40% {
    transform: translateY(calc(var(--dock-lift, 0) - 6px)) scale(var(--dock-scale, 1));
  }

  100% {
    transform: translateY(var(--dock-lift, 0)) scale(var(--dock-scale, 1));
  }
}

@media (max-width: 768px) {
  .desktop-dock {
    width: calc(100% - 20px);
    justify-content: flex-start;
    gap: 6px;
    overflow-x: auto;
  }

  .dock-entry {
    display: flex;
    flex: 0 0 auto;
    justify-content: center;
  }

  .dock-item {
    width: 46px;
    height: 46px;
  }
}

@media (prefers-reduced-motion: reduce) {
  .dock-app-enter-active,
  .dock-app-leave-active,
  .dock-app-move {
    transition-duration: 1ms;
  }
}

@media (hover: hover) and (pointer: fine) {
  .desktop-dock.dock-auto-hide:not(.dock-expanded) {
    transform: translateX(-50%) translateY(100%);
  }

  .dock-hover-zone:hover .desktop-dock.dock-auto-hide:not(.dock-expanded),
  .desktop-dock.dock-auto-hide:not(.dock-expanded):focus-within {
    transform: translateX(-50%);
  }
}
</style>

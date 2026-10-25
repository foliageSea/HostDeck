<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch, type CSSProperties } from 'vue'
import DesktopMenu from './DesktopMenu.vue'
import DesktopTooltip from './DesktopTooltip.vue'
import AppIcon from './AppIcon.vue'
import { useDockMagnification } from './useDockMagnification'
import {
  useDesktopContext,
  useDesktop as useDesktopStore,
  useDesktopPreferences as useSettingsStore,
} from './context'
import type { AppConfig } from '../core/types'
import { calculateDockScale } from '../core/dock-layout'
type DesktopAppId = string

const context = useDesktopContext()
const preloadAppIcons = (icons: Iterable<string>) => context.preloadIcons?.(icons)

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const emit = defineEmits<{
  openLaunchpad: []
}>()
const selectorTarget = ref<HTMLElement | null>(null)
const hoverZone = ref<HTMLElement | null>(null)
const selectorPanel = ref<HTMLElement | null>(null)
const selectorAppId = ref<DesktopAppId | null>(null)
const bouncingAppId = ref<DesktopAppId | null>(null)
const draggedAppId = ref<DesktopAppId | null>(null)
const dragOverAppId = ref<DesktopAppId | null>(null)
const dragOverSide = ref<'before' | 'after'>('before')
const dockScale = ref(1)
let dockResizeObserver: ResizeObserver | undefined
const isVertical = computed(() => settingsStore.dockPosition !== 'bottom')
const dockAxis = computed(() => (isVertical.value ? 'vertical' : 'horizontal'))
const tooltipSide = computed(() => {
  if (settingsStore.dockPosition === 'left') return 'right'
  if (settingsStore.dockPosition === 'right') return 'left'
  return 'top'
})
useDockMagnification(
  selectorTarget,
  computed(() => Boolean(draggedAppId.value)),
  dockAxis,
)
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
  const appIndex = desktopStore.dockAppIds.indexOf(appId)
  return [
    { key: 'new', label: '新建窗口', disabled: !desktopStore.canOpenWindow(appId) },
    {
      key: 'move-left',
      label: isVertical.value ? '向上移动' : '向左移动',
      disabled: appIndex <= 0,
    },
    {
      key: 'move-right',
      label: isVertical.value ? '向下移动' : '向右移动',
      disabled: appIndex === -1 || appIndex >= desktopStore.dockAppIds.length - 1,
    },
    { key: 'unpin', label: '从 Dock 移除' },
    ...(hasWindows ? [{ key: 'close-all', label: '关闭全部窗口', danger: true }] : []),
  ]
})

const dockApps = computed<AppConfig[]>(() =>
  desktopStore.dockAppIds
    .map((appId) => desktopStore.apps[appId])
    .filter((app): app is AppConfig => Boolean(app?.showInLaunchpad)),
)
const childWindows = computed(() =>
  desktopStore.windows.filter((window) => window.parentId && !window.isClosing),
)
const dockStyle = computed<CSSProperties>(() => {
  const scale = dockScale.value
  const dockRadius =
    settingsStore.cornerStyle === 'square'
      ? 0
      : settingsStore.cornerStyle === 'soft'
        ? 10 * scale
        : 18 * scale
  return {
    '--dock-gap': `${12 * scale}px`,
    '--dock-item-size': `${52 * scale}px`,
    '--dock-padding': `${10 * scale}px`,
    '--dock-running-indicator-offset': `${7 * scale}px`,
    '--dock-running-indicator-size': `${Math.max(3, 5 * scale)}px`,
    '--dock-separator-size': `${34 * scale}px`,
    '--dock-track-edge-padding': `${20 * scale}px`,
    borderRadius: `${dockRadius}px`,
  }
})
const dockIconSize = computed(() => 52 * dockScale.value)

function updateDockScale() {
  const zone = hoverZone.value
  if (!zone) return

  const vertical = isVertical.value
  const edgeClearance = vertical ? 28 : 100
  const availableSize = (vertical ? zone.clientHeight : zone.clientWidth) - edgeClearance
  dockScale.value = calculateDockScale({
    availableSize,
    itemCount: 1 + dockApps.value.length + childWindows.value.length,
    separatorCount: childWindows.value.length > 0 ? 2 : 1,
    vertical,
  })
}

watch(
  () => [
    ...dockApps.value.map((app) => app.icon),
    ...childWindows.value.map((window) => window.icon),
  ],
  (icons) => {
    void preloadAppIcons(icons)
  },
  { immediate: true },
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
  updateDockScale()
  if (typeof ResizeObserver !== 'undefined' && hoverZone.value) {
    dockResizeObserver = new ResizeObserver(updateDockScale)
    dockResizeObserver.observe(hoverZone.value)
  }
})

onUnmounted(() => {
  window.removeEventListener('pointerdown', handleGlobalPointerDown, true)
  dockResizeObserver?.disconnect()
})

watch(
  [() => dockApps.value.length, () => childWindows.value.length, () => settingsStore.dockPosition],
  async () => {
    await nextTick()
    updateDockScale()
  },
)

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
      x:
        settingsStore.dockPosition === 'left'
          ? rect.right + 12
          : settingsStore.dockPosition === 'right'
            ? rect.left - 12
            : rect.left + rect.width / 2,
      y: settingsStore.dockPosition === 'bottom' ? rect.top - 12 : rect.top + rect.height / 2,
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
  const target = event.currentTarget
  if (target instanceof HTMLElement) {
    const rect = target.getBoundingClientRect()
    dragOverSide.value = isVertical.value
      ? event.clientY < rect.top + target.offsetHeight / 2
        ? 'before'
        : 'after'
      : event.clientX < rect.left + target.offsetWidth / 2
        ? 'before'
        : 'after'
  }
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
  dragOverSide.value = 'before'
}

function openLaunchpad() {
  closeSelector()
  contextMenu.value = null
  emit('openLaunchpad')
}
</script>

<template>
  <div
    ref="hoverZone"
    class="dock-hover-zone absolute z-20 flex justify-center"
    :data-position="settingsStore.dockPosition"
  >
    <footer
      ref="selectorTarget"
      class="app-radius-card desktop-dock relative"
      :class="{
        'dock-auto-hide': settingsStore.dockAutoHide,
        'dock-expanded': isDockExpanded,
        'dock-dragging': draggedAppId,
        'dock-dark': settingsStore.isDark,
      }"
      :data-position="settingsStore.dockPosition"
      :style="dockStyle"
      @contextmenu.prevent
    >
      <div class="dock-track" :class="{ 'dock-track-vertical': isVertical }">
        <DesktopTooltip :side="tooltipSide">
          <template #trigger>
            <button
              type="button"
              class="launchpad-trigger dock-item flex shrink-0 items-center justify-center border-0 bg-transparent p-0 cursor-pointer"
              data-dock-slot
              aria-label="打开启动台"
              @click="openLaunchpad"
            >
              <svg
                class="launchpad-icon"
                viewBox="0 0 128 128"
                :width="dockIconSize"
                :height="dockIconSize"
                aria-hidden="true"
              >
                <defs>
                  <linearGradient
                    id="launchpad-bg"
                    x1="64"
                    y1="6"
                    x2="64"
                    y2="122"
                    gradientUnits="userSpaceOnUse"
                  >
                    <stop stop-color="#F7F8FB" />
                    <stop offset="1" stop-color="#B9BFCC" />
                  </linearGradient>
                  <linearGradient
                    id="launchpad-rim"
                    x1="20"
                    y1="8"
                    x2="64"
                    y2="70"
                    gradientUnits="userSpaceOnUse"
                  >
                    <stop stop-color="#FFFFFF" />
                    <stop offset="1" stop-color="#FFFFFF" stop-opacity="0" />
                  </linearGradient>
                  <linearGradient id="launchpad-blue" x1="0" y1="0" x2="0" y2="1">
                    <stop stop-color="#5AC8FA" />
                    <stop offset="1" stop-color="#2F7BF5" />
                  </linearGradient>
                  <linearGradient id="launchpad-green" x1="0" y1="0" x2="0" y2="1">
                    <stop stop-color="#6EE7A0" />
                    <stop offset="1" stop-color="#22A861" />
                  </linearGradient>
                  <linearGradient id="launchpad-orange" x1="0" y1="0" x2="0" y2="1">
                    <stop stop-color="#FFC15A" />
                    <stop offset="1" stop-color="#F97316" />
                  </linearGradient>
                  <linearGradient id="launchpad-pink" x1="0" y1="0" x2="0" y2="1">
                    <stop stop-color="#FF8FB0" />
                    <stop offset="1" stop-color="#E11D48" />
                  </linearGradient>
                  <linearGradient id="launchpad-purple" x1="0" y1="0" x2="0" y2="1">
                    <stop stop-color="#A78BFA" />
                    <stop offset="1" stop-color="#6D28D9" />
                  </linearGradient>
                  <linearGradient id="launchpad-slate" x1="0" y1="0" x2="0" y2="1">
                    <stop stop-color="#6B7280" />
                    <stop offset="1" stop-color="#374151" />
                  </linearGradient>
                </defs>
                <rect x="6" y="6" width="116" height="116" rx="30" fill="url(#launchpad-bg)" />
                <rect
                  x="6.75"
                  y="6.75"
                  width="114.5"
                  height="114.5"
                  rx="29.25"
                  fill="none"
                  stroke="url(#launchpad-rim)"
                  stroke-width="1.5"
                />
                <rect x="28" y="28" width="20" height="20" rx="6" fill="url(#launchpad-blue)" />
                <rect x="54" y="28" width="20" height="20" rx="6" fill="url(#launchpad-green)" />
                <rect x="80" y="28" width="20" height="20" rx="6" fill="url(#launchpad-orange)" />
                <rect x="28" y="54" width="20" height="20" rx="6" fill="url(#launchpad-pink)" />
                <rect x="54" y="54" width="20" height="20" rx="6" fill="url(#launchpad-purple)" />
                <rect x="80" y="54" width="20" height="20" rx="6" fill="url(#launchpad-slate)" />
                <rect x="28" y="80" width="20" height="20" rx="6" fill="url(#launchpad-orange)" />
                <rect x="54" y="80" width="20" height="20" rx="6" fill="url(#launchpad-blue)" />
                <rect x="80" y="80" width="20" height="20" rx="6" fill="url(#launchpad-green)" />
              </svg>
            </button>
          </template>
          启动台
        </DesktopTooltip>

        <span
          class="dock-separator shrink-0 bg-[rgba(148,163,184,0.3)]"
          data-dock-slot
          aria-hidden="true"
        />

        <TransitionGroup
          name="dock-app"
          tag="div"
          class="dock-apps dock-section relative flex shrink-0 items-center"
        >
          <div
            v-for="app in dockApps"
            :key="app.id"
            class="dock-entry relative"
            data-dock-slot
            :data-running="isAppOpen(app.id)"
            :class="{
              'dock-entry-dragging': draggedAppId === app.id,
              'dock-entry-drag-over': dragOverAppId === app.id,
              'dock-entry-drag-over-before': dragOverAppId === app.id && dragOverSide === 'before',
              'dock-entry-drag-over-after': dragOverAppId === app.id && dragOverSide === 'after',
            }"
            draggable="true"
            @dragstart="handleDragStart($event, app.id)"
            @dragover="handleDragOver($event, app.id)"
            @dragleave="dragOverAppId = null"
            @drop="handleDrop($event, app.id)"
            @dragend="handleDragEnd"
          >
            <DesktopTooltip :side="tooltipSide">
              <template #trigger>
                <button
                  class="dock-item relative flex items-center justify-center border-0 bg-transparent p-0 cursor-pointer"
                  type="button"
                  :aria-label="app.title"
                  @click="handleOpen($event, app.id)"
                  @contextmenu="handleContextMenu($event, app.id)"
                  @keydown="handleTriggerKeydown($event, app.id)"
                >
                  <span
                    class="dock-artwork"
                    :class="{ 'dock-item-bounce': bouncingAppId === app.id }"
                  >
                    <AppIcon :name="app.icon" :size="dockIconSize" themed />
                  </span>
                </button>
              </template>
              {{ app.title }}
            </DesktopTooltip>
            <span
              v-if="isAppOpen(app.id)"
              class="dock-running-indicator absolute bottom-[-7px] left-1/2 translate-x-[-50%] rounded-full bg-[var(--app-primary-color)]"
              aria-hidden="true"
            />
          </div>
        </TransitionGroup>

        <template v-if="childWindows.length > 0">
          <span
            class="dock-separator shrink-0 bg-[rgba(148,163,184,0.3)]"
            data-dock-slot
            aria-hidden="true"
          />

          <TransitionGroup
            name="dock-app"
            tag="div"
            class="dock-child-windows dock-section relative flex shrink-0 items-center"
            aria-label="已打开的子窗口"
          >
            <div
              v-for="window in childWindows"
              :key="window.id"
              class="dock-entry dock-child-window-entry relative"
              data-dock-slot
              :data-dock-window-id="window.id"
              :data-running="true"
            >
              <DesktopTooltip :side="tooltipSide">
                <template #trigger>
                  <button
                    type="button"
                    class="dock-item dock-child-window-item relative flex items-center justify-center border-0 bg-transparent p-0 cursor-pointer"
                    :class="{ 'dock-child-window-minimized': window.isMinimized }"
                    :aria-label="`切换到${window.title}`"
                    @click="activateWindow(window.id)"
                  >
                    <span class="dock-artwork">
                      <AppIcon :name="window.icon" :size="dockIconSize" themed />
                    </span>
                  </button>
                </template>
                {{ window.title }}
              </DesktopTooltip>
              <span
                class="dock-running-indicator absolute bottom-[-7px] left-1/2 translate-x-[-50%] rounded-full"
                :class="
                  desktopStore.activeWindowId === window.id
                    ? 'bg-[var(--app-primary-color)]'
                    : settingsStore.isDark
                      ? 'bg-[rgba(148,163,184,0.64)]'
                      : 'bg-[rgba(100,116,139,0.58)]'
                "
                aria-hidden="true"
              />
            </div>
          </TransitionGroup>
        </template>
      </div>

      <Teleport
        :to="context.overlayTarget?.value ?? 'body'"
        :disabled="!context.overlayTarget?.value"
      >
        <div
          v-if="selectorAppId && selectorPosition"
          ref="selectorPanel"
          class="app-radius-surface dock-window-selector fixed z-[9999] w-[220px] rounded-[16px] p-[10px]"
          :class="[
            settingsStore.isDark
              ? 'border border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.9)] shadow-[0_24px_70px_rgba(2,6,23,0.35)]'
              : 'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.94)] shadow-[0_24px_70px_rgba(148,163,184,0.22)]',
          ]"
          :style="{
            left: `${selectorPosition.x}px`,
            top: `${selectorPosition.y}px`,
          }"
          :data-position="settingsStore.dockPosition"
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
            <button
              type="button"
              class="webos-button rounded-[6px] px-[10px] py-[4px]"
              :disabled="!desktopStore.canOpenWindow(selectorAppId)"
              @click="openNewWindow(selectorAppId)"
            >
              新建窗口
            </button>
            <button
              type="button"
              class="webos-button webos-danger rounded-[6px] px-[10px] py-[4px]"
              @click="closeAppWindows(selectorAppId)"
            >
              关闭全部
            </button>
          </div>
        </div>
      </Teleport>

      <DesktopMenu
        :show="Boolean(contextMenu)"
        :x="contextMenu?.x ?? 0"
        :y="contextMenu?.y ?? 0"
        :options="contextMenuOptions"
        @close="closeContextMenu"
        @select="handleContextMenuSelect"
      />
    </footer>
  </div>
</template>

<style scoped>
.dock-hover-zone[data-position='bottom'] {
  right: 0;
  bottom: 0;
  left: 0;
  height: 12px;
  align-items: flex-end;
}

.dock-hover-zone[data-position='left'],
.dock-hover-zone[data-position='right'] {
  top: var(--desktop-topbar-height);
  bottom: 0;
  width: 12px;
  align-items: center;
}

.dock-hover-zone[data-position='left'] {
  left: 0;
  justify-content: flex-start;
}

.dock-hover-zone[data-position='right'] {
  right: 0;
  justify-content: flex-end;
}

.desktop-dock[data-position='bottom'] {
  margin-bottom: var(--desktop-dock-edge-gap);
}

.desktop-dock[data-position='left'] {
  margin-left: var(--desktop-dock-edge-gap);
}

.desktop-dock[data-position='right'] {
  margin-right: var(--desktop-dock-edge-gap);
}

.dock-entry {
  display: flex;
  flex-shrink: 0;
  align-items: flex-end;
}

.dock-entry,
.dock-separator {
  /* Keep lateral magnification separate from TransitionGroup's FLIP transform. */
  translate: var(--dock-shift, 0px) 0;
  transition: translate var(--dock-motion-duration) cubic-bezier(0.22, 1, 0.36, 1);
}

.desktop-dock[data-position='left'] .dock-entry,
.desktop-dock[data-position='left'] .dock-separator,
.desktop-dock[data-position='right'] .dock-entry,
.desktop-dock[data-position='right'] .dock-separator {
  translate: 0 var(--dock-shift, 0px);
}

.dock-entry[data-running='true'] {
  --dock-lift: -2px;
}

.desktop-dock[data-position='left'] .dock-entry[data-running='true'] {
  --dock-lift: 2px;
}

.desktop-dock[data-position='right'] .dock-entry[data-running='true'] {
  --dock-lift: -2px;
}

.dock-entry-dragging {
  opacity: 0.28;
  filter: saturate(0.7);
}

.dock-entry-drag-over::before {
  position: absolute;
  inset: 0;
  border: 1px dashed color-mix(in srgb, var(--app-primary-color) 70%, transparent);
  border-radius: 17px;
  background: color-mix(in srgb, var(--app-primary-color) 10%, transparent);
  pointer-events: none;
  content: '';
}

.dock-entry-drag-over::after {
  position: absolute;
  top: -5px;
  bottom: -5px;
  width: 3px;
  border-radius: 999px;
  background: var(--app-primary-color);
  box-shadow:
    0 0 0 3px color-mix(in srgb, var(--app-primary-color) 18%, transparent),
    0 0 12px color-mix(in srgb, var(--app-primary-color) 55%, transparent);
  pointer-events: none;
  content: '';
  z-index: 2;
}

.desktop-dock[data-position='left'] .dock-entry-drag-over::after,
.desktop-dock[data-position='right'] .dock-entry-drag-over::after {
  right: -5px;
  left: -5px;
  width: auto;
  height: 3px;
}

.dock-entry-drag-over-before::after {
  left: -8px;
}

.dock-entry-drag-over-after::after {
  right: -8px;
}

.desktop-dock[data-position='left'] .dock-entry-drag-over-before::after,
.desktop-dock[data-position='right'] .dock-entry-drag-over-before::after {
  top: -8px;
  right: -5px;
  bottom: auto;
  left: -5px;
}

.desktop-dock[data-position='left'] .dock-entry-drag-over-after::after,
.desktop-dock[data-position='right'] .dock-entry-drag-over-after::after {
  top: auto;
  right: -5px;
  bottom: -8px;
  left: -5px;
}

.dock-app-enter-active,
.dock-app-leave-active,
.dock-app-move {
  transition:
    opacity 220ms ease,
    transform 260ms cubic-bezier(0.16, 1, 0.3, 1),
    translate var(--dock-motion-duration) cubic-bezier(0.22, 1, 0.36, 1);
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
  --dock-motion-duration: 360ms;
  display: flex;
  width: max-content;
  max-width: calc(100vw - 100px);
  max-height: calc(100vh - var(--desktop-topbar-height) - 28px);
  border: 1px solid transparent;
  padding: var(--dock-padding);
  /* No transform and no isolation here: either one turns the dock into the backdrop root of
     ::before, so the blur would sample the dock itself instead of the wallpaper. */
  transform: none;
  transition: transform 280ms cubic-bezier(0.22, 1, 0.36, 1);
}

.desktop-dock[data-magnifying='true'] {
  --dock-motion-duration: 180ms;
}

.desktop-dock::before {
  position: absolute;
  z-index: 0;
  top: -1px;
  bottom: -1px;
  left: calc(-1px - var(--dock-expansion, 0px) / 2);
  right: calc(-1px - var(--dock-expansion, 0px) / 2);
  border: 1px solid rgba(148, 163, 184, 0.22);
  border-radius: inherit;
  background: rgba(255, 255, 255, 0.36);
  backdrop-filter: blur(16px) saturate(145%);
  box-shadow:
    0 8px 28px rgba(15, 23, 42, 0.12),
    0 1px 0 rgba(255, 255, 255, 0.2) inset;
  transition:
    left var(--dock-motion-duration) cubic-bezier(0.22, 1, 0.36, 1),
    right var(--dock-motion-duration) cubic-bezier(0.22, 1, 0.36, 1);
  pointer-events: none;
  content: '';
}

.desktop-dock[data-position='left']::before,
.desktop-dock[data-position='right']::before {
  top: calc(-1px - var(--dock-expansion, 0px) / 2);
  bottom: calc(-1px - var(--dock-expansion, 0px) / 2);
  left: -1px;
  right: -1px;
  transition:
    top var(--dock-motion-duration) cubic-bezier(0.22, 1, 0.36, 1),
    bottom var(--dock-motion-duration) cubic-bezier(0.22, 1, 0.36, 1);
}

.desktop-dock.dock-dark::before {
  border-color: rgba(148, 163, 184, 0.16);
  background: rgba(15, 23, 42, 0.3);
  box-shadow:
    0 8px 28px rgba(2, 6, 23, 0.24),
    0 1px 0 rgba(255, 255, 255, 0.08) inset;
}

.dock-track {
  position: relative;
  display: flex;
  min-width: 0;
  align-items: center;
  gap: var(--dock-gap);
  overflow-x: auto;
  /* Let enlarged icons, the launch bounce, and running dots fit inside the scrollport. */
  padding: 40px 40px 10px;
  margin: -40px -40px -10px;
  scrollbar-width: none;
}

.dock-track-vertical {
  max-height: none;
  min-height: 0;
  flex-direction: column;
  overflow-x: visible;
  overflow-y: visible;
  padding: var(--dock-track-edge-padding) var(--dock-padding) var(--dock-track-edge-padding) 40px;
  margin: 0 calc(-1 * var(--dock-padding)) 0 -40px;
}

.desktop-dock[data-position='right'] .dock-track-vertical {
  padding: var(--dock-track-edge-padding) 40px var(--dock-track-edge-padding) var(--dock-padding);
  margin: 0 -40px 0 calc(-1 * var(--dock-padding));
}

.dock-track-vertical .dock-section {
  flex-direction: column;
}

.dock-section {
  gap: var(--dock-gap);
}

.dock-track-vertical .dock-separator {
  width: var(--dock-separator-size);
  height: 1px;
}

.desktop-dock[data-position='bottom'] .dock-separator {
  width: 1px;
  height: var(--dock-separator-size);
}

.dock-track::-webkit-scrollbar {
  display: none;
}

.dock-item {
  width: var(--dock-item-size);
  height: var(--dock-item-size);
  transform: translateY(var(--dock-lift, 0px)) scale(var(--dock-scale, 1));
  transform-origin: center bottom;
  transition:
    transform var(--dock-motion-duration) cubic-bezier(0.22, 1, 0.36, 1),
    background-color 160ms ease;
}

.launchpad-trigger {
  translate: var(--dock-shift, 0px) 0;
  transition:
    translate var(--dock-motion-duration) cubic-bezier(0.22, 1, 0.36, 1),
    transform var(--dock-motion-duration) cubic-bezier(0.22, 1, 0.36, 1),
    background-color 160ms ease;
}

.desktop-dock[data-position='left'] .launchpad-trigger,
.desktop-dock[data-position='right'] .launchpad-trigger {
  translate: 0 var(--dock-shift, 0px);
}

.desktop-dock[data-position='left'] .dock-item {
  transform: translateX(var(--dock-lift, 0px)) scale(var(--dock-scale, 1));
  transform-origin: left center;
}

.desktop-dock[data-position='right'] .dock-item {
  transform: translateX(var(--dock-lift, 0px)) scale(var(--dock-scale, 1));
  transform-origin: right center;
}

.desktop-dock[data-position='left'] .dock-item:active {
  transform: translateX(var(--dock-lift, 0px)) scale(calc(var(--dock-scale, 1) * 0.94));
}

.desktop-dock[data-position='right'] .dock-item:active {
  transform: translateX(var(--dock-lift, 0px)) scale(calc(var(--dock-scale, 1) * 0.94));
}

.desktop-dock[data-position='left'] .dock-running-indicator,
.desktop-dock[data-position='right'] .dock-running-indicator {
  top: 50%;
  bottom: auto;
  translate: 0 -50%;
  transform: none;
}

.dock-running-indicator {
  width: var(--dock-running-indicator-size);
  height: var(--dock-running-indicator-size);
}

/* 指示点贴向屏幕边缘：左侧 Dock 在最左，右侧 Dock 在最右 */
.desktop-dock[data-position='left'] .dock-running-indicator {
  left: calc(-1 * var(--dock-running-indicator-offset));
}

.desktop-dock[data-position='right'] .dock-running-indicator {
  left: auto;
  right: calc(-1 * var(--dock-running-indicator-offset));
}

.desktop-dock[data-position='bottom'] .dock-running-indicator {
  bottom: calc(-1 * var(--dock-running-indicator-offset));
}

.dock-window-selector[data-position='bottom'] {
  transform: translate(-50%, -100%);
}

.dock-window-selector[data-position='left'] {
  transform: translateY(-50%);
}

.dock-window-selector[data-position='right'] {
  transform: translate(-100%, -50%);
}

.launchpad-icon {
  display: block;
  pointer-events: none;
}

.dock-item:focus-visible {
  outline: 2px solid var(--app-primary-color);
  outline-offset: 4px;
  border-radius: 16px;
}

.dock-item:active {
  transform: translateY(var(--dock-lift, 0px)) scale(calc(var(--dock-scale, 1) * 0.94));
}

.dock-artwork {
  display: flex;
  pointer-events: none;
}

.dock-child-window-minimized .dock-artwork {
  opacity: 0.58;
  filter: saturate(0.72);
}

.dock-item-bounce {
  animation: dock-bounce 0.38s ease;
}

@keyframes dock-bounce {
  0%,
  100% {
    transform: translateY(0);
  }

  40% {
    transform: translateY(-6px);
  }
}

@media (max-width: 768px) {
  .dock-track,
  .dock-apps,
  .dock-child-windows {
    gap: var(--dock-gap);
  }

  .dock-entry {
    display: flex;
    flex: 0 0 auto;
    justify-content: center;
  }
}

@media (prefers-reduced-motion: reduce) {
  .desktop-dock,
  .desktop-dock::before,
  .dock-item,
  .dock-entry,
  .dock-separator,
  .dock-app-enter-active,
  .dock-app-leave-active,
  .dock-app-move {
    transition-duration: 1ms;
  }

  .dock-item-bounce {
    animation: none;
  }
}

@media (hover: hover) and (pointer: fine) {
  .desktop-dock.dock-auto-hide:not(.dock-expanded) {
    transform: translateY(100%);
  }

  .desktop-dock[data-position='left'].dock-auto-hide:not(.dock-expanded) {
    transform: translateX(-100%);
  }

  .desktop-dock[data-position='right'].dock-auto-hide:not(.dock-expanded) {
    transform: translateX(100%);
  }

  .dock-hover-zone:hover .desktop-dock.dock-auto-hide:not(.dock-expanded),
  .desktop-dock.dock-auto-hide:not(.dock-expanded):focus-within {
    transform: none;
  }
}
</style>

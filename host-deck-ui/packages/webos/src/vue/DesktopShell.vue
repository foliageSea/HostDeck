<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { NDropdown, type DropdownOption } from 'naive-ui'
import type { CSSProperties } from 'vue'
import { matchesKeyboardShortcut } from '../core/keyboard-shortcut'
import { desktopThemeStyle } from '../core/preferences'
import {
  useDesktopContext,
  useDesktop as useDesktopStore,
  useDesktopPreferences as useSettingsStore,
} from './context'
import DesktopDock from './DesktopDock.vue'
import DesktopLaunchpad from './DesktopLaunchpad.vue'
import DesktopWindow from './DesktopWindow.vue'
import DesktopWindowSwitcher from './DesktopWindowSwitcher.vue'
import DesktopWidgets from './DesktopWidgets.vue'

const props = defineProps<{
  wallpaperStyle?: CSSProperties
  wallpaperFilter?: string
  videoWallpaperUrl?: string
  wallpaperClass?: string
}>()
const context = useDesktopContext()
const rootElement = ref<HTMLElement | null>(null)
const contentElement = ref<HTMLElement | null>(null)
const themeStyle = desktopThemeStyle(context.preferences)
let resizeObserver: ResizeObserver | undefined
let isActive = true

const emit = defineEmits<{
  ready: []
}>()

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const widgetStore = context.widgets
const switcherVisible = ref(false)
const launchpadVisible = ref(false)
const switcherIndex = ref(0)
const switcherWindows = ref<typeof desktopStore.windows>([])
const directSwitchActive = ref(false)
const desktopContextMenu = ref<{ x: number; y: number } | null>(null)

const windows = computed(() => desktopStore.windows)
const desktopDockSafeArea = computed(() =>
  settingsStore.dockAutoHide
    ? 'var(--desktop-dock-bottom-gap)'
    : 'calc(var(--desktop-dock-bottom-gap) + var(--desktop-dock-height))',
)
const desktopContextMenuOptions = computed<DropdownOption[]>(() => [
  {
    key: 'widgets',
    label: '添加小组件',
    children: Object.keys(widgetStore?.definitions ?? {}).map((type) => {
      const definition = widgetStore!.definitions[type]!
      return {
        disabled: Boolean(definition.singleInstance && widgetStore!.hasWidget(type)),
        key: `add-widget:${type}`,
        label:
          definition.singleInstance && widgetStore!.hasWidget(type)
            ? `${definition.title}（已添加）`
            : definition.title,
      }
    }),
  },
])

function handleDesktopContextMenuSelect(key: string | number) {
  if (typeof key === 'string' && key.startsWith('add-widget:')) {
    widgetStore?.addWidget(key.slice('add-widget:'.length))
  }
  desktopContextMenu.value = null
}

function selectWindow(index: number) {
  const targetWindow = switcherWindows.value[index]
  if (!targetWindow) {
    return
  }

  desktopStore.focusWindow(targetWindow.id)
  switcherVisible.value = false
  directSwitchActive.value = false
}

async function closeSwitcherWindow(id: string) {
  try {
    await desktopStore.requestCloseWindow(id)
  } catch (error) {
    desktopStore.reportLifecycleError(error)
    return
  }

  const targetWindow = desktopStore.windows.find((window) => window.id === id)
  if (targetWindow && !targetWindow.isClosing) {
    return
  }

  switcherWindows.value = switcherWindows.value.filter((window) => !window.isClosing)
  if (switcherWindows.value.length === 0) {
    switcherVisible.value = false
    return
  }

  switcherIndex.value = Math.min(switcherIndex.value, switcherWindows.value.length - 1)
}

function handleKeyDown(event: KeyboardEvent) {
  if (!isActive) return
  if (event.target instanceof Element && event.target.closest('[data-shortcut-recorder]')) {
    return
  }

  if (event.key === 'Escape' && launchpadVisible.value) {
    event.preventDefault()
    event.stopPropagation()
    launchpadVisible.value = false
    return
  }

  if (launchpadVisible.value) {
    return
  }

  if (event.key === 'Escape' && switcherVisible.value) {
    event.preventDefault()
    event.stopPropagation()
    switcherVisible.value = false
    directSwitchActive.value = false
    return
  }

  const isSwitcherToggleKey = matchesKeyboardShortcut(
    event,
    settingsStore.windowSwitcherToggleShortcut,
  )
  const isDirectSwitchKey = matchesKeyboardShortcut(event, settingsStore.windowSwitchShortcut)
  if (!isSwitcherToggleKey && !isDirectSwitchKey) {
    return
  }

  event.preventDefault()
  event.stopPropagation()

  const sortedWindows = desktopStore.windows
    .filter((window) => !window.isClosing)
    .sort((left, right) => right.zIndex - left.zIndex)
  if (sortedWindows.length < 2) {
    return
  }

  if (isDirectSwitchKey && !isSwitcherToggleKey) {
    if (!switcherVisible.value || !directSwitchActive.value) {
      switcherWindows.value = sortedWindows
      switcherIndex.value = 1
      switcherVisible.value = true
      directSwitchActive.value = true
      return
    }

    switcherIndex.value = (switcherIndex.value + 1) % switcherWindows.value.length
    return
  }

  if (event.repeat) {
    return
  }

  if (switcherVisible.value) {
    switcherVisible.value = false
    directSwitchActive.value = false
    return
  }

  switcherWindows.value = sortedWindows
  switcherIndex.value = 0
  switcherVisible.value = true
  directSwitchActive.value = false
}

function handleKeyUp(event: KeyboardEvent) {
  if (!directSwitchActive.value || !switcherVisible.value) {
    return
  }

  const shortcut = settingsStore.windowSwitchShortcut
  const releasedRequiredModifier =
    (event.key === 'Alt' && shortcut.altKey) ||
    (event.key === 'Control' && (shortcut.ctrlKey || shortcut.ctrlOrMeta)) ||
    (event.key === 'Meta' && (shortcut.metaKey || shortcut.ctrlOrMeta)) ||
    (event.key === 'Shift' && shortcut.shiftKey)
  if (releasedRequiredModifier) {
    selectWindow(switcherIndex.value)
  }
}

function updateBounds() {
  const element = contentElement.value
  if (element) desktopStore.setBounds(element.clientWidth, element.clientHeight)
}

function handlePointerDown(event: PointerEvent) {
  isActive = event.target instanceof Node && Boolean(rootElement.value?.contains(event.target))
}

onMounted(() => {
  if (context.overlayTarget) context.overlayTarget.value = rootElement.value
  updateBounds()
  if (typeof ResizeObserver !== 'undefined' && contentElement.value) {
    resizeObserver = new ResizeObserver(updateBounds)
    resizeObserver.observe(contentElement.value)
  }
  window.addEventListener('resize', updateBounds)
  document.addEventListener('pointerdown', handlePointerDown, true)
  window.addEventListener('keydown', handleKeyDown, true)
  window.addEventListener('keyup', handleKeyUp, true)
  emit('ready')
})

onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  if (context.overlayTarget?.value === rootElement.value) context.overlayTarget.value = null
  window.removeEventListener('resize', updateBounds)
  document.removeEventListener('pointerdown', handlePointerDown, true)
  window.removeEventListener('keydown', handleKeyDown, true)
  window.removeEventListener('keyup', handleKeyUp, true)
})
</script>

<template>
  <div
    ref="rootElement"
    class="webos-root desktop-shell"
    :data-theme="settingsStore.isDark ? 'dark' : 'light'"
    :style="{ ...themeStyle, '--desktop-dock-safe-area': desktopDockSafeArea }"
  >
    <video
      v-if="props.videoWallpaperUrl"
      class="absolute inset-0 h-full w-full object-cover"
      :src="props.videoWallpaperUrl"
      :style="{ filter: props.wallpaperFilter }"
      autoplay
      muted
      loop
      playsinline
    />
    <div
      v-else
      class="absolute inset-0 bg-cover bg-center bg-no-repeat"
      :class="props.wallpaperClass"
      :style="props.wallpaperStyle ?? { background: settingsStore.isDark ? '#0b1220' : '#d8e0e8' }"
    />
    <div class="absolute inset-0 [backdrop-filter:saturate(108%)]" />

    <slot name="topbar">
      <header class="webos-topbar"><slot name="brand">WebOS</slot><slot name="status" /></header>
    </slot>

    <main
      ref="contentElement"
      class="absolute z-0 [inset:var(--desktop-topbar-height)_0_var(--desktop-dock-safe-area)]"
      @contextmenu.self.prevent="desktopContextMenu = { x: $event.clientX, y: $event.clientY }"
    >
      <slot
        name="desktop"
        :show-context-menu="(position: { x: number; y: number }) => (desktopContextMenu = position)"
      >
        <DesktopWidgets v-if="widgetStore" />
      </slot>
      <TransitionGroup name="desktop-window-anim" tag="div" class="relative h-full w-full">
        <DesktopWindow v-for="window in windows" :key="window.id" :window="window" />
      </TransitionGroup>
    </main>

    <DesktopDock @open-launchpad="launchpadVisible = true" />

    <DesktopLaunchpad :show="launchpadVisible" @close="launchpadVisible = false" />

    <NDropdown
      :to="context.overlayTarget?.value ?? false"
      trigger="manual"
      placement="bottom-start"
      :show="Boolean(desktopContextMenu)"
      :x="desktopContextMenu?.x ?? 0"
      :y="desktopContextMenu?.y ?? 0"
      :options="desktopContextMenuOptions"
      @clickoutside="desktopContextMenu = null"
      @select="handleDesktopContextMenuSelect"
    />

    <DesktopWindowSwitcher
      v-if="switcherVisible"
      :windows="switcherWindows"
      :selected-index="switcherIndex"
      @close="closeSwitcherWindow"
      @highlight="switcherIndex = $event"
      @select="selectWindow"
    />
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
  .desktop-shell {
    --desktop-dock-height: 68px;
  }

  .desktop-status-card {
    left: 16px;
    right: 16px;
    bottom: calc(var(--desktop-dock-safe-area) - 18px);
    width: auto;
  }
}
</style>

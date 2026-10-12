<script setup lang="ts">
import { computed, ref, shallowRef } from 'vue'
import { DesktopShell, provideDesktopContext } from '@host-deck/webos'
import { createWallpaperFilter, createWallpaperStyle } from '@/lib/wallpapers'
import { themedAppIconMap, preloadAppIcons } from '@/lib/app-icons'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useDesktopWidgetStore } from '@/stores/desktop-widget'
import type { AppIconKey } from '@/types/desktop'
import DesktopTopBar from './DesktopTopBar.vue'
import DesktopPinnedDirectories from './DesktopPinnedDirectories.vue'
import DesktopWidgets from '@/components/widgets/DesktopWidgets.vue'

const emit = defineEmits<{ ready: [] }>()
const settings = useSettingsStore()
provideDesktopContext({
  desktop: useDesktopStore().runtime,
  preferences: settings,
  widgets: useDesktopWidgetStore().runtime,
  resolveIcon: (name) => themedAppIconMap[name as AppIconKey],
  preloadIcons: (names) => preloadAppIcons(Array.from(names) as AppIconKey[]),
  overlayTarget: shallowRef(null),
})
const shortcutGridCells = ref<string[]>([])
const wallpaperStyle = computed(() =>
  createWallpaperStyle('desktop', settings.desktopWallpaper, settings.isDark),
)
const wallpaperFilter = computed(() => createWallpaperFilter(settings.desktopWallpaper))
const videoWallpaperUrl = computed(() => {
  const wallpaper = settings.desktopWallpaper
  if (wallpaper.mode !== 'custom' || wallpaper.customType !== 'video' || !wallpaper.customDataUrl)
    return undefined
  const url = wallpaper.customDataUrl
  if (url.startsWith('/') && import.meta.env.DEV && import.meta.env.VITE_DEV_PROXY_TARGET) {
    try {
      return new URL(url, import.meta.env.VITE_DEV_PROXY_TARGET).toString()
    } catch {
      return url
    }
  }
  return url
})
</script>

<template>
  <DesktopShell
    :wallpaper-style="wallpaperStyle"
    :wallpaper-filter="wallpaperFilter"
    :video-wallpaper-url="videoWallpaperUrl"
    :wallpaper-class="
      settings.desktopWallpaper.mode === 'default' ? 'default-wallpaper-motion' : undefined
    "
    @ready="emit('ready')"
  >
    <template #topbar><DesktopTopBar /></template>
    <template #desktop="{ showContextMenu }">
      <DesktopPinnedDirectories
        @blank-context-menu="showContextMenu"
        @grid-occupancy-change="shortcutGridCells = $event"
      />
      <DesktopWidgets :blocked-grid-cells="shortcutGridCells" />
    </template>
  </DesktopShell>
</template>

<style scoped>
.desktop-shell {
  height: 100vh;
  font-family: inherit;
}
:global(:root[data-electron='true']) .desktop-shell {
  height: calc(100vh - var(--electron-titlebar-height));
}
:global(:root[data-electron-shell='native-tabs']) .desktop-shell {
  height: 100vh;
}
</style>

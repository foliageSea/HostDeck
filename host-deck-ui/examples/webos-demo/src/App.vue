<script setup lang="ts">
import { computed, onBeforeUnmount, reactive } from 'vue'
import { NConfigProvider, darkTheme } from 'naive-ui'
import {
  DesktopProvider,
  DesktopShell,
  DesktopShortcuts,
  DesktopWidgets,
  type DesktopShortcut,
} from '@host-deck/webos'
import { createDemoDesktop } from './desktop'

const context = createDemoDesktop()
const shortcuts = reactive<DesktopShortcut[]>([
  {
    id: 'welcome-shortcut',
    title: '打开欢迎',
    icon: context.desktop.apps.welcome!.icon,
    x: 20,
    y: 20,
    open: () => {
      context.desktop.openWindow('welcome')
    },
  },
])
const theme = computed(() => (context.preferences.isDark ? darkTheme : null))
function moveShortcut(id: string, x: number, y: number) {
  const item = shortcuts.find((shortcut) => shortcut.id === id)
  if (item) {
    item.x = x
    item.y = y
  }
}
onBeforeUnmount(() => context.desktop.dispose())
</script>

<template>
  <NConfigProvider :theme="theme">
    <div class="demo-desktop">
      <DesktopProvider :context="context">
        <DesktopShell>
          <template #brand>WebOS Demo</template>
          <template #status>
            <button type="button" @click="context.preferences.isDark = !context.preferences.isDark">
              切换主题
            </button>
          </template>
          <template #desktop>
            <DesktopShortcuts :shortcuts="shortcuts" @move="moveShortcut" />
            <DesktopWidgets />
          </template>
        </DesktopShell>
      </DesktopProvider>
    </div>
  </NConfigProvider>
</template>

<style>
html,
body,
#app {
  width: 100%;
  height: 100%;
  margin: 0;
  overflow: hidden;
}
body {
  background: #f1f5f9;
  font-family: system-ui, sans-serif;
}
.demo-desktop {
  position: fixed;
  inset: 0;
  overflow: hidden;
}
</style>

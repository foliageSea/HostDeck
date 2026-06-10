<script setup lang="ts">
import { computed, ref } from 'vue'
import { Debug, Launch } from '@vicons/carbon'

const isMaximized = ref(false)
const isMac = computed(() => window.hostDeck?.platform === 'darwin')

async function minimizeWindow() {
  await window.hostDeck?.window?.minimize()
}

async function toggleMaximizeWindow() {
  const nextState = await window.hostDeck?.window?.toggleMaximize()
  isMaximized.value = Boolean(nextState)
}

async function closeWindow() {
  await window.hostDeck?.window?.close()
}

async function openInBrowser() {
  await window.hostDeck?.app?.openInBrowser()
}

async function openDevTools() {
  await window.hostDeck?.app?.openDevTools()
}
</script>

<template>
  <header class="electron-titlebar">
    <div v-if="!isMac" class="electron-titlebar__controls" aria-label="窗口控制">
      <button class="electron-titlebar__button electron-titlebar__button--close" type="button" aria-label="关闭" @click="closeWindow" />
      <button class="electron-titlebar__button electron-titlebar__button--minimize" type="button" aria-label="最小化" @click="minimizeWindow" />
      <button class="electron-titlebar__button electron-titlebar__button--maximize" type="button" :aria-label="isMaximized ? '还原' : '最大化'" @click="toggleMaximizeWindow" />
    </div>
    <div class="electron-titlebar__drag-region">
      <span class="electron-titlebar__title">HostDeck</span>
    </div>
    <div class="electron-titlebar__actions">
      <button class="electron-titlebar__action" type="button" aria-label="打开开发者工具" title="打开开发者工具" @click="openDevTools">
        <NIcon :size="15">
          <Debug />
        </NIcon>
      </button>
      <button class="electron-titlebar__action" type="button" aria-label="在外部浏览器打开" title="在外部浏览器打开" @click="openInBrowser">
        <NIcon :size="15">
          <Launch />
        </NIcon>
      </button>
    </div>
  </header>
</template>

<style scoped>
.electron-titlebar {
  position: fixed;
  inset: 0 0 auto;
  z-index: 1000;
  display: flex;
  height: var(--electron-titlebar-height);
  align-items: center;
  border-bottom: 1px solid rgba(255, 255, 255, 0.12);
  background: #000;
  color: rgba(255, 255, 255, 0.86);
  -webkit-app-region: drag;
}

:global(:root[data-theme='light']) .electron-titlebar {
  border-bottom-color: rgba(15, 23, 42, 0.12);
  background: #fff;
  color: rgba(0, 0, 0, 0.78);
}

.electron-titlebar__controls {
  display: flex;
  gap: 8px;
  align-items: center;
  padding-left: 14px;
  -webkit-app-region: no-drag;
}

.electron-titlebar__button {
  position: relative;
  width: 12px;
  height: 12px;
  padding: 0;
  border: 0;
  border-radius: 999px;
  box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.16);
  cursor: default;
}

.electron-titlebar__button--close {
  background: #ff5f57;
}

.electron-titlebar__button--minimize {
  background: #ffbd2e;
}

.electron-titlebar__button--maximize {
  background: #28c840;
}

.electron-titlebar__drag-region {
  display: flex;
  flex: 1;
  justify-content: center;
  min-width: 0;
  padding-right: 42px;
}

.electron-titlebar__title {
  overflow: hidden;
  max-width: 45vw;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.02em;
  opacity: 0.78;
}

.electron-titlebar__actions {
  display: flex;
  align-items: center;
  padding-right: 12px;
  -webkit-app-region: no-drag;
}

.electron-titlebar__action {
  display: inline-flex;
  width: 28px;
  height: 28px;
  align-items: center;
  justify-content: center;
  padding: 0;
  border: 0;
  border-radius: 8px;
  background: transparent;
  color: currentColor;
  cursor: default;
  opacity: 0.76;
}

.electron-titlebar__action:hover {
  background: rgba(255, 255, 255, 0.12);
  opacity: 1;
}

:global(:root[data-theme='light']) .electron-titlebar__action:hover {
  background: rgba(15, 23, 42, 0.08);
}

@media (max-width: 640px) {
  .electron-titlebar__drag-region {
    justify-content: flex-start;
    padding-right: 12px;
    padding-left: 18px;
  }
}
</style>

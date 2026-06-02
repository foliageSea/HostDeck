<script setup lang="ts">
import { ref } from 'vue'

const isMaximized = ref(false)

async function minimizeWindow() {
  await window.sshTool?.window?.minimize()
}

async function toggleMaximizeWindow() {
  const nextState = await window.sshTool?.window?.toggleMaximize()
  isMaximized.value = Boolean(nextState)
}

async function closeWindow() {
  await window.sshTool?.window?.close()
}

async function openInBrowser() {
  await window.sshTool?.app?.openInBrowser()
}
</script>

<template>
  <header class="electron-titlebar">
    <div class="electron-titlebar__controls" aria-label="窗口控制">
      <button class="electron-titlebar__button electron-titlebar__button--close" type="button" aria-label="关闭" @click="closeWindow" />
      <button class="electron-titlebar__button electron-titlebar__button--minimize" type="button" aria-label="最小化" @click="minimizeWindow" />
      <button class="electron-titlebar__button electron-titlebar__button--maximize" type="button" :aria-label="isMaximized ? '还原' : '最大化'" @click="toggleMaximizeWindow" />
    </div>
    <div class="electron-titlebar__drag-region">
      <span class="electron-titlebar__title">HostDeck</span>
    </div>
    <div class="electron-titlebar__actions">
      <button class="electron-titlebar__action" type="button" aria-label="在外部浏览器打开" title="在外部浏览器打开" @click="openInBrowser">
        <svg viewBox="0 0 16 16" aria-hidden="true" focusable="false">
          <path d="M9 2h5v5h-1.5V4.56L7.53 9.53 6.47 8.47l4.97-4.97H9V2Z" />
          <path d="M3.5 4h3v1.5h-3v7h7v-3H12v3.25c0 .69-.56 1.25-1.25 1.25h-7.5C2.56 14 2 13.44 2 12.75v-7.5C2 4.56 2.56 4 3.25 4h.25Z" />
        </svg>
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

.electron-titlebar__action svg {
  width: 15px;
  height: 15px;
  fill: currentColor;
}

@media (max-width: 640px) {
  .electron-titlebar__drag-region {
    justify-content: flex-start;
    padding-right: 12px;
    padding-left: 18px;
  }
}
</style>

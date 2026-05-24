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
</script>

<template>
  <header class="electron-titlebar">
    <div class="electron-titlebar__controls" aria-label="窗口控制">
      <button class="electron-titlebar__button electron-titlebar__button--close" type="button" aria-label="关闭" @click="closeWindow" />
      <button class="electron-titlebar__button electron-titlebar__button--minimize" type="button" aria-label="最小化" @click="minimizeWindow" />
      <button class="electron-titlebar__button electron-titlebar__button--maximize" type="button" :aria-label="isMaximized ? '还原' : '最大化'" @click="toggleMaximizeWindow" />
    </div>
    <div class="electron-titlebar__drag-region">
      <span class="electron-titlebar__title">SSH Tool</span>
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
  background: rgba(15, 23, 42, 0.58);
  color: rgba(255, 255, 255, 0.82);
  backdrop-filter: blur(22px) saturate(140%);
  -webkit-app-region: drag;
}

:global(:root[data-theme='light']) .electron-titlebar {
  border-bottom-color: rgba(15, 23, 42, 0.1);
  background: rgba(248, 250, 252, 0.78);
  color: rgba(15, 23, 42, 0.74);
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
  padding-right: 92px;
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

@media (max-width: 640px) {
  .electron-titlebar__drag-region {
    justify-content: flex-start;
    padding-right: 12px;
    padding-left: 18px;
  }
}
</style>

<script setup lang="ts">
import { computed } from 'vue'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const desktopStore = useDesktopStore()

const currentTime = computed(() =>
  new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date()),
)

function disconnect() {
  getUiApi().dialog.warning({
    title: '断开连接',
    content: '确认结束当前 SSH 会话并返回登录页？',
    positiveText: '断开',
    negativeText: '取消',
    onPositiveClick: () => {
      desktopStore.reset()
      sshStore.clearSession()
    },
  })
}
</script>

<template>
  <header class="desktop-topbar">
    <div class="desktop-topbar-section">
      <span class="topbar-brand">SSH Tool</span>
    </div>

    <div class="desktop-topbar-section desktop-topbar-center">
      <span>{{ sshStore.host || '未连接主机' }}</span>
    </div>

    <div class="desktop-topbar-section">
      <NButton text @click="disconnect">断开</NButton>
      <NButton text @click="settingsStore.toggleTheme">
        {{ settingsStore.isDark ? '浅色' : '深色' }}
      </NButton>
      <span>{{ currentTime }}</span>
    </div>
  </header>
</template>

<style scoped>
.desktop-topbar {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 48px;
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  padding: 0 16px;
  background: rgba(15, 23, 42, 0.45);
  border-bottom: 1px solid rgba(148, 163, 184, 0.16);
  backdrop-filter: blur(16px);
  z-index: 20;
}

.desktop-topbar-section {
  display: flex;
  align-items: center;
  gap: 12px;
  color: #e2e8f0;
  min-width: 0;
}

.desktop-topbar-center {
  justify-content: center;
  font-size: 0.92rem;
  color: rgba(226, 232, 240, 0.8);
}

.desktop-topbar-section:last-child {
  justify-content: flex-end;
}

.topbar-brand {
  font-weight: 700;
  letter-spacing: 0.04em;
}
</style>

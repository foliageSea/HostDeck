<script setup lang="ts">
import { computed } from 'vue'
import { Logout, Moon, Sun } from '@vicons/carbon'
import { getUiApi } from '@/lib/ui'
import DesktopTaskCenter from '@/components/os/DesktopTaskCenter.vue'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import type { DesktopAppId } from '@/types/desktop'

const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const desktopStore = useDesktopStore()

const currentTime = computed(() =>
  new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date()),
)
const sessionStatusMeta = computed(() => {
  if (sshStore.sessionStatus === 'connected') {
    return {
      className: settingsStore.isDark ? 'bg-emerald-400' : 'bg-emerald-500',
      label: 'SSH 会话已连接',
    }
  }

  if (sshStore.sessionStatus === 'reconnecting') {
    return {
      className: settingsStore.isDark ? 'bg-amber-300 animate-pulse' : 'bg-amber-500 animate-pulse',
      label: 'SSH 会话重连中',
    }
  }

  if (sshStore.sessionStatus === 'connecting') {
    return {
      className: settingsStore.isDark ? 'bg-sky-300 animate-pulse' : 'bg-sky-500 animate-pulse',
      label: 'SSH 会话连接中',
    }
  }

  return {
    className: settingsStore.isDark ? 'bg-slate-500' : 'bg-slate-400',
    label: '当前未连接 SSH 会话',
  }
})
const appMenuOptions = computed(() => [
  { key: 'runtime-sessions', label: '会话管理' },
  { key: 'settings', label: '设置' },
])
const monitorData = computed(() => sshStore.monitorData)
const monitorError = computed(() => sshStore.monitorError)
const cpuUsage = computed(() => {
  if (typeof monitorData.value?.cpuUsage === 'number') {
    return `${monitorData.value.cpuUsage.toFixed(1)}%`
  }

  return '--'
})
const memoryUsage = computed(() => {
  const ram = monitorData.value?.ram
  if (!ram?.total) {
    return '--'
  }

  return `${Math.round((ram.used / ram.total) * 100)}%`
})
const uploadSpeed = computed(() => formatSpeed(monitorData.value?.network?.uploadSpeed ?? 0))
const downloadSpeed = computed(() => formatSpeed(monitorData.value?.network?.downloadSpeed ?? 0))
const performanceStats = computed(() => [
  { label: 'CPU', value: cpuUsage.value },
  { label: '上传', value: uploadSpeed.value },
  { label: '内存', value: memoryUsage.value },
  { label: '下载', value: downloadSpeed.value },
])
function formatSpeed(value: number) {
  if (value >= 1024 * 1024) {
    return `${(value / 1024 / 1024).toFixed(2)} MB/s`
  }

  if (value >= 1024) {
    return `${(value / 1024).toFixed(1)} KB/s`
  }

  return `${value.toFixed(0)} B/s`
}

function handleAppMenuSelect(key: string | number) {
  desktopStore.openWindow(key as DesktopAppId)
}

function disconnect() {
  const dialog = getUiApi().dialog.warning({
    title: '断开连接',
    content: '确认结束当前 SSH 会话并返回登录页？',
    positiveText: '断开',
    negativeText: '取消',
    onPositiveClick: async () => {
      dialog.loading = true
      try {
        desktopStore.reset()
        sshStore.clearSession()
      } finally {
        dialog.loading = false
      }
    },
  })
}
</script>

<template>
  <header
    class="absolute left-0 right-0 top-0 z-20 grid h-[var(--desktop-topbar-height)] grid-cols-[1fr_auto_1fr] items-center border-b px-[12px] backdrop-blur-[16px]"
    :class="[
      settingsStore.isDark
        ? 'border-[rgba(148,163,184,0.16)] bg-[rgba(15,23,42,0.45)] text-[#e2e8f0]'
        : 'border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.58)] text-[#1e293b]',
    ]"
  >
    <div class="flex min-w-0 items-center gap-[8px]">
      <NDropdown :options="appMenuOptions" trigger="click" @select="handleAppMenuSelect">
        <button
          type="button"
          class="flex min-w-0 items-center gap-[8px] rounded-[12px] border-0 px-[8px] py-[3px] cursor-pointer transition-colors"
          :class="
            settingsStore.isDark
              ? 'bg-[rgba(15,23,42,0.26)] text-[rgba(226,232,240,0.9)] hover:bg-[rgba(30,41,59,0.54)]'
              : 'bg-[rgba(255,255,255,0.46)] text-[rgba(30,41,59,0.9)] hover:bg-[rgba(255,255,255,0.76)]'
          "
          aria-label="打开 HostDeck 菜单"
        >
          <img class="h-[22px] w-[22px] flex-none object-contain" src="/favicon.png" alt="HostDeck" />
          <span class="truncate text-[12px] font-700 tracking-[0.02em] lt-sm:hidden">HostDeck</span>
        </button>
      </NDropdown>
    </div>

    <div
      class="flex min-w-0 items-center justify-center gap-[8px] text-[0.88rem]"
      :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.8)]' : 'text-[rgba(51,65,85,0.82)]'"
    >
      <NTooltip placement="bottom">
        <template #trigger>
          <span
            class="h-[10px] w-[10px] shrink-0 rounded-full shadow-[0_0_0_3px_rgba(148,163,184,0.12)]"
            :class="sessionStatusMeta.className"
            :aria-label="sessionStatusMeta.label"
          />
        </template>
        {{ sessionStatusMeta.label }}
      </NTooltip>
      <NTooltip placement="bottom">
        <template #trigger>
          <div
            class="flex min-w-[120px] max-w-[320px] items-center justify-between gap-[8px] rounded-[10px] px-[10px] py-[3px] text-[12px]"
            :class="
              settingsStore.isDark
                ? 'bg-[rgba(15,23,42,0.46)] text-[rgba(226,232,240,0.88)]'
                : 'bg-[rgba(255,255,255,0.58)] text-[rgba(30,41,59,0.88)]'
            "
          >
            <span class="shrink-0 text-[rgba(148,163,184,0.94)]">IP</span>
            <strong class="truncate font-600">{{ sshStore.host || '未连接主机' }}</strong>
          </div>
        </template>
        {{ sshStore.host || '未连接主机' }}
      </NTooltip>
      <NTooltip v-if="monitorError" placement="bottom">
        <template #trigger>
          <div
            class="flex items-center gap-[8px] rounded-[10px] border px-[10px] py-[3px] text-[12px]"
            :class="
              settingsStore.isDark
                ? 'border-[rgba(248,113,113,0.3)] bg-[rgba(127,29,29,0.28)] text-[rgba(254,202,202,0.96)]'
                : 'border-[rgba(239,68,68,0.24)] bg-[rgba(254,242,242,0.9)] text-[rgba(185,28,28,0.92)]'
            "
          >
            <span class="h-[8px] w-[8px] shrink-0 rounded-full bg-[currentColor] opacity-90" />
            <strong class="font-600">监控异常</strong>
          </div>
        </template>
        {{ monitorError }}
      </NTooltip>
    </div>

    <div class="flex min-w-0 items-center justify-end gap-[8px]">
      <div class="hidden grid-cols-2 gap-[2px] xl:grid">
        <div
          v-for="stat in performanceStats"
          :key="stat.label"
          class="flex min-w-[74px] items-center justify-between gap-[5px] px-[6px] py-[2px] text-[10px] leading-[1.1]"
          :class="
            settingsStore.isDark ? 'text-[rgba(226,232,240,0.88)]' : 'text-[rgba(30,41,59,0.88)]'
          "
        >
          <span>{{ stat.label }}</span>
          <strong class="whitespace-nowrap font-600">{{ stat.value }}</strong>
        </div>
      </div>
      <DesktopTaskCenter />

      <NButton quaternary circle @click="disconnect">
        <template #icon>
          <NIcon :size="16">
            <Logout />
          </NIcon>
        </template>
      </NButton>
      <NButton quaternary circle @click="settingsStore.toggleTheme">
        <template #icon>
          <NIcon :size="16">
            <component :is="settingsStore.isDark ? Sun : Moon" />
          </NIcon>
        </template>
      </NButton>
      <span>{{ currentTime }}</span>
    </div>
  </header>
</template>

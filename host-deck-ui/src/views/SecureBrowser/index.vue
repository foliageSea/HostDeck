<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  secureBrowserApi,
  type SecureBrowserCapabilities,
  type SecureBrowserTunnel,
} from '@/api/secure-browser'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const loading = ref(false)
const starting = ref(false)
const operatingId = ref<string | null>(null)
const tunnels = ref<SecureBrowserTunnel[]>([])
const capabilities = ref<SecureBrowserCapabilities>({
  launchEnabled: false,
  chromeDetected: false,
})

const hasConnection = computed(() => Boolean(sshStore.connectionId && sshStore.isConnected))
const connectionText = computed(() => {
  if (!hasConnection.value) return '未连接 SSH'
  return `${sshStore.username}@${sshStore.host}:${sshStore.port}`
})
const canLaunch = computed(
  () =>
    hasConnection.value &&
    (Boolean(window.hostDeck?.app?.openInSecureChrome) || capabilities.value.launchEnabled),
)

async function fetchTunnels() {
  loading.value = true
  try {
    const items = await secureBrowserApi.list()
    tunnels.value = items.filter((tunnel) => tunnel.connectionId === sshStore.connectionId)
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '加载安全浏览器会话失败。')
  } finally {
    loading.value = false
  }
}

async function fetchCapabilities() {
  if (window.hostDeck?.app?.openInSecureChrome) return
  try {
    capabilities.value = await secureBrowserApi.capabilities()
  } catch {
    capabilities.value = { launchEnabled: false, chromeDetected: false }
  }
}

async function launchTunnelInChrome(tunnel: SecureBrowserTunnel) {
  const launcher = window.hostDeck?.app?.openInSecureChrome
  if (launcher) {
    const result = await launcher({
      profileId: tunnel.id,
      proxyPort: tunnel.bindPort,
    })
    if (!result.success) throw new Error(result.message)
    return
  }
  if (!capabilities.value.launchEnabled) {
    throw new Error('Dart CLI 未启用安全浏览器启动功能。')
  }
  await secureBrowserApi.launch(tunnel.id)
}

async function startSecureBrowser() {
  if (!window.hostDeck?.app?.openInSecureChrome && !capabilities.value.launchEnabled) {
    getUiApi().message.warning('请使用 --enable-secure-browser 启动 Dart CLI 后再使用安全浏览器。')
    return
  }
  if (!hasConnection.value) {
    getUiApi().message.warning('启动安全浏览器前请先连接 SSH。')
    return
  }

  starting.value = true
  try {
    const tunnel = await secureBrowserApi.create({
      connectionId: sshStore.connectionId as string,
    })
    if (!tunnels.value.some((item) => item.id === tunnel.id)) tunnels.value.unshift(tunnel)
    try {
      await launchTunnelInChrome(tunnel)
      getUiApi().message.success('安全浏览器已启动。')
    } catch (error) {
      getUiApi().message.error(
        `${error instanceof Error ? error.message : 'Chrome 启动失败。'} 代理会话已保留，可稍后重试或手动停止。`,
      )
    }
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '创建安全浏览器会话失败。')
  } finally {
    starting.value = false
  }
}

async function reopenTunnel(tunnel: SecureBrowserTunnel) {
  operatingId.value = tunnel.id
  try {
    await launchTunnelInChrome(tunnel)
    getUiApi().message.success('已打开新的 Chrome 窗口。')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : 'Chrome 启动失败。')
  } finally {
    operatingId.value = null
  }
}

async function stopTunnel(tunnel: SecureBrowserTunnel) {
  operatingId.value = tunnel.id
  try {
    await secureBrowserApi.stop(tunnel.id)
    tunnels.value = tunnels.value.filter((item) => item.id !== tunnel.id)
    getUiApi().message.success('安全浏览器代理已停止。')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '停止安全浏览器代理失败。')
  } finally {
    operatingId.value = null
  }
}

onMounted(() => {
  void fetchTunnels()
  void fetchCapabilities()
})
</script>

<template>
  <div
    class="secure-browser-view flex h-full flex-col gap-[16px] overflow-auto p-[20px]"
    :class="
      settingsStore.isDark
        ? 'bg-[radial-gradient(circle_at_top_left,rgba(34,197,94,0.12),transparent_32%),rgba(15,23,42,0.04)]'
        : 'bg-[radial-gradient(circle_at_top_left,rgba(34,197,94,0.14),transparent_32%),rgba(248,250,252,0.58)]'
    "
  >
    <div class="flex flex-wrap items-start justify-between gap-[12px]">
      <div class="text-[24px] font-700 leading-tight">安全浏览器</div>
      <NSpace>
        <NButton secondary :loading="loading" @click="fetchTunnels">刷新</NButton>
        <NButton
          type="primary"
          :disabled="!canLaunch"
          :loading="starting"
          @click="startSecureBrowser"
        >
          启动浏览器
        </NButton>
      </NSpace>
    </div>

    <div class="grid grid-cols-2 gap-[12px] lt-md:grid-cols-1">
      <NCard size="small">
        <div class="text-[12px] text-[rgba(100,116,139,0.86)]">当前连接</div>
        <div class="mt-[8px] flex items-center gap-[8px] text-[15px] font-600">
          <NTag :type="hasConnection ? 'success' : 'warning'" size="small">
            {{ hasConnection ? '已连接' : '未连接' }}
          </NTag>
          <span>{{ connectionText }}</span>
        </div>
      </NCard>
      <NCard size="small">
        <div class="text-[12px] text-[rgba(100,116,139,0.86)]">运行中的代理</div>
        <div class="mt-[8px] text-[26px] font-700 text-[#16a34a]">{{ tunnels.length }}</div>
      </NCard>
    </div>

    <NCard class="min-h-0 flex-1" content-style="height: 100%; padding: 0;" :bordered="false">
      <div v-if="loading" class="flex h-full min-h-[280px] items-center justify-center">
        <NSpin size="large" />
      </div>
      <NEmpty
        v-else-if="tunnels.length === 0"
        class="py-[76px]"
        description="暂无运行中的安全浏览器代理"
      >
        <template #extra>
          <NButton
            type="primary"
            :disabled="!canLaunch"
            :loading="starting"
            @click="startSecureBrowser"
          >
            启动安全浏览器
          </NButton>
        </template>
      </NEmpty>
      <div v-else class="divide-y divide-[rgba(148,163,184,0.16)]">
        <div
          v-for="tunnel in tunnels"
          :key="tunnel.id"
          class="flex flex-wrap items-center justify-between gap-[16px] p-[16px]"
        >
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-[8px]">
              <div class="truncate text-[15px] font-700">安全浏览器会话</div>
              <NTag size="small" type="success">运行中</NTag>
            </div>
            <div class="mt-[6px] text-[12px] text-[rgba(100,116,139,0.82)]">
              本地代理 {{ tunnel.bindHost }}:{{ tunnel.bindPort }}
            </div>
          </div>
          <NSpace>
            <NButton
              size="small"
              type="primary"
              :loading="operatingId === tunnel.id"
              @click="reopenTunnel(tunnel)"
            >
              打开新窗口
            </NButton>
            <NButton
              size="small"
              secondary
              type="error"
              :loading="operatingId === tunnel.id"
              @click="stopTunnel(tunnel)"
            >
              停止
            </NButton>
          </NSpace>
        </div>
      </div>
    </NCard>
  </div>
</template>

<style scoped>
.secure-browser-view::-webkit-scrollbar {
  width: 0;
  height: 0;
  display: none;
}
</style>

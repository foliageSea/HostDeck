<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { AppWindow, Play, Power, RefreshCw, ShieldCheck } from '@lucide/vue'
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
const activeTunnel = computed(() => tunnels.value[0] ?? null)
const connectionText = computed(() => {
  if (!hasConnection.value) return '未连接 SSH'
  return `${sshStore.username}@${sshStore.host}:${sshStore.port}`
})
const canLaunch = computed(
  () =>
    hasConnection.value &&
    (Boolean(window.hostDeck?.app?.openInSecureChrome) || capabilities.value.launchEnabled),
)
const capabilityText = computed(() => {
  if (canLaunch.value) {
    return window.hostDeck?.app?.openInSecureChrome ? '桌面环境已就绪' : 'CLI 启动已就绪'
  }
  if (!hasConnection.value) return '请先建立 SSH 连接'
  return '需要启用安全浏览器功能'
})

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

function refreshAll() {
  void fetchTunnels()
  void fetchCapabilities()
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
        `${error instanceof Error ? error.message : 'Chrome 启动失败。'} 代理会话已保留，可稍后停止。`,
      )
    }
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '创建安全浏览器会话失败。')
  } finally {
    starting.value = false
  }
}

async function stopTunnel(tunnel: SecureBrowserTunnel) {
  operatingId.value = tunnel.id
  try {
    await secureBrowserApi.stop(tunnel.id)
    tunnels.value = tunnels.value.filter((item) => item.id !== tunnel.id)
    getUiApi().message.success('安全浏览器已停止。')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '停止安全浏览器失败。')
  } finally {
    operatingId.value = null
  }
}

async function toggleSecureBrowser() {
  if (activeTunnel.value) {
    await stopTunnel(activeTunnel.value)
    return
  }
  await startSecureBrowser()
}

function formatTime(timestamp: number) {
  return new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(new Date(timestamp))
}

onMounted(() => {
  void fetchTunnels()
  void fetchCapabilities()
})
</script>

<template>
  <div class="secure-browser-view" :class="{ 'secure-browser-dark': settingsStore.isDark }">
    <section class="sb-control-card" aria-labelledby="sb-title">
      <header class="sb-card-header">
        <div class="sb-title-group">
          <div class="sb-title-icon" aria-hidden="true">
            <ShieldCheck :size="22" />
          </div>
          <div>
            <h1 id="sb-title">安全浏览器</h1>
            <p>通过 SSH 隔离访问远程网络</p>
          </div>
        </div>
        <NTooltip>
          <template #trigger>
            <NButton
              quaternary
              circle
              size="small"
              :loading="loading"
              aria-label="刷新浏览器状态"
              @click="refreshAll"
            >
              <template #icon><RefreshCw :size="15" /></template>
            </NButton>
          </template>
          刷新状态
        </NTooltip>
      </header>

      <div class="sb-status-panel" :class="{ 'sb-status-active': activeTunnel }">
        <div class="sb-status-icon" aria-hidden="true">
          <AppWindow :size="28" />
        </div>
        <div class="sb-status-copy">
          <span class="sb-eyebrow">会话状态</span>
          <strong>{{ activeTunnel ? '浏览器正在运行' : '浏览器尚未启动' }}</strong>
          <span class="sb-muted">
            {{
              activeTunnel
                ? `代理 ${activeTunnel.bindHost}:${activeTunnel.bindPort} · 已启动 ${formatTime(activeTunnel.startedAt)}`
                : hasConnection
                  ? '启动后将打开独立的 Chrome 窗口'
                  : '请先连接 SSH'
            }}
          </span>
        </div>
        <span class="sb-status-badge" :class="{ 'sb-status-badge-active': activeTunnel }">
          <span class="sb-status-dot" />{{ activeTunnel ? '运行中' : '未启动' }}
        </span>
      </div>

      <div class="sb-connection-row">
        <div class="sb-connection-heading">
          <span class="sb-eyebrow">SSH 连接</span>
          <strong :class="{ 'sb-text-muted': !hasConnection }">{{ connectionText }}</strong>
        </div>
        <span class="sb-capability-text" :class="{ 'sb-text-muted': !canLaunch }">
          {{ capabilityText }}
        </span>
      </div>

      <div class="sb-action-area">
        <NButton
          class="sb-main-action"
          size="large"
          :type="activeTunnel ? 'error' : 'primary'"
          :disabled="!activeTunnel && !canLaunch"
          :loading="starting || Boolean(operatingId)"
          @click="toggleSecureBrowser"
        >
          <template #icon>
            <Power v-if="activeTunnel" :size="17" />
            <Play v-else :size="17" />
          </template>
          {{ activeTunnel ? '停止安全浏览器' : '启动安全浏览器' }}
        </NButton>
        <small v-if="!hasConnection" class="sb-action-hint"> 建立 SSH 连接后即可启动 </small>
        <small v-else-if="!canLaunch" class="sb-action-hint">
          当前服务未启用安全浏览器启动功能
        </small>
      </div>
    </section>
  </div>
</template>

<style scoped>
.secure-browser-view {
  --sb-border: rgba(148, 163, 184, 0.2);
  --sb-surface: rgba(255, 255, 255, 0.76);
  --sb-header: rgba(148, 163, 184, 0.06);
  --sb-muted: #64748b;
  --sb-primary: #2563eb;
  --sb-primary-soft: rgba(37, 99, 235, 0.12);
  --sb-ok: #15803d;
  --sb-ok-soft: rgba(34, 197, 94, 0.11);
  display: grid;
  height: 100%;
  min-height: 0;
  overflow: auto;
  padding: 24px;
  place-items: center;
}

.secure-browser-dark {
  --sb-border: rgba(148, 163, 184, 0.14);
  --sb-surface: rgba(30, 32, 42, 0.72);
  --sb-header: rgba(255, 255, 255, 0.025);
  --sb-muted: #a1a1aa;
  --sb-primary: #60a5fa;
  --sb-primary-soft: rgba(96, 165, 250, 0.14);
  --sb-ok: #4ade80;
  --sb-ok-soft: rgba(34, 197, 94, 0.12);
}

.sb-control-card {
  width: min(100%, 600px);
  overflow: hidden;
  border: 1px solid var(--sb-border);
  border-radius: var(--app-radius-card, 12px);
  background: var(--sb-surface);
  box-shadow: 0 18px 50px rgba(15, 23, 42, 0.08);
  backdrop-filter: blur(18px);
}

.secure-browser-dark .sb-control-card {
  box-shadow: 0 18px 50px rgba(0, 0, 0, 0.18);
}

.sb-card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 22px 24px;
  border-bottom: 1px solid var(--sb-border);
  background: var(--sb-header);
}

.sb-title-group {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 13px;
}

.sb-title-icon {
  display: grid;
  flex: none;
  width: 44px;
  height: 44px;
  color: var(--sb-primary);
  border-radius: 12px;
  background: var(--sb-primary-soft);
  place-items: center;
}

.sb-card-header h1 {
  margin: 0;
  font-size: 18px;
  font-weight: 700;
  letter-spacing: -0.01em;
}

.sb-card-header p {
  margin: 5px 0 0;
  color: var(--sb-muted);
  font-size: 12px;
}

.sb-status-panel {
  display: flex;
  align-items: center;
  gap: 14px;
  margin: 20px 24px 0;
  padding: 16px;
  border: 1px solid var(--sb-border);
  border-radius: 10px;
  background: rgba(148, 163, 184, 0.06);
}

.sb-status-active {
  border-color: rgba(34, 197, 94, 0.24);
  background: var(--sb-ok-soft);
}

.sb-status-icon {
  display: grid;
  flex: none;
  width: 46px;
  height: 46px;
  color: var(--sb-muted);
  border-radius: 50%;
  background: rgba(148, 163, 184, 0.13);
  place-items: center;
}

.sb-status-active .sb-status-icon {
  color: var(--sb-ok);
  background: rgba(34, 197, 94, 0.14);
}

.sb-status-copy {
  display: flex;
  min-width: 0;
  flex: 1;
  flex-direction: column;
  gap: 4px;
}

.sb-status-copy strong {
  font-size: 14px;
  font-weight: 650;
}

.sb-status-copy .sb-muted {
  overflow: hidden;
  font-size: 12px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sb-eyebrow {
  color: var(--sb-muted);
  font-size: 11px;
  line-height: 1.2;
}

.sb-status-badge {
  display: inline-flex;
  flex: none;
  align-items: center;
  gap: 6px;
  padding: 5px 9px;
  color: var(--sb-muted);
  border-radius: 999px;
  background: rgba(148, 163, 184, 0.12);
  font-size: 12px;
  white-space: nowrap;
}

.sb-status-badge-active {
  color: var(--sb-ok);
  background: rgba(34, 197, 94, 0.12);
}

.sb-status-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
}

.sb-connection-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin: 20px 24px 0;
  padding-bottom: 18px;
  border-bottom: 1px solid var(--sb-border);
}

.sb-connection-heading {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 5px;
}

.sb-connection-heading strong {
  overflow: hidden;
  font-size: 13px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sb-capability-text {
  flex: none;
  color: var(--sb-ok);
  font-size: 12px;
}

.sb-text-muted {
  color: var(--sb-muted);
}

.sb-muted {
  color: var(--sb-muted);
}

.sb-action-area {
  display: flex;
  align-items: center;
  flex-direction: column;
  gap: 9px;
  padding: 24px;
}

.sb-main-action {
  width: min(100%, 280px);
}

.sb-action-hint {
  color: var(--sb-muted);
  font-size: 11px;
}

@media (max-width: 560px) {
  .secure-browser-view {
    padding: 12px;
  }

  .sb-card-header,
  .sb-status-panel,
  .sb-connection-row,
  .sb-action-area {
    padding-left: 16px;
    padding-right: 16px;
  }

  .sb-status-panel,
  .sb-connection-row {
    margin-left: 16px;
    margin-right: 16px;
  }

  .sb-connection-row {
    align-items: flex-start;
    flex-direction: column;
    gap: 8px;
  }
}

@media (max-width: 400px) {
  .sb-status-panel {
    align-items: flex-start;
    flex-wrap: wrap;
  }

  .sb-status-badge {
    margin-left: 60px;
  }
}
</style>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { AppWindow, Lock, Play, RefreshCw, ShieldCheck } from '@lucide/vue'
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
const launchModeText = computed(() => {
  if (window.hostDeck?.app?.openInSecureChrome) return '桌面环境直接启动'
  if (capabilities.value.launchEnabled) {
    return capabilities.value.chromeDetected ? 'CLI 启动 Chrome' : 'CLI 启动（未检测到 Chrome）'
  }
  return '未启用（需 --enable-secure-browser）'
})

const features = [
  {
    title: '隔离环境',
    desc: '独立的浏览器配置与数据目录，与日常浏览互不影响。',
    icon: ShieldCheck,
  },
  {
    title: '安全代理',
    desc: '全部流量经 SSH 隧道以 SOCKS5 转发，直连远程网络。',
    icon: Lock,
  },
  {
    title: '单实例',
    desc: '每个连接仅保留一个会话，可随时停止并释放端口。',
    icon: AppWindow,
  },
]

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
    if (activeTunnel.value) {
      await launchTunnelInChrome(activeTunnel.value)
      getUiApi().message.success('安全浏览器已打开。')
      return
    }

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
    <div class="sb-grid">
      <section class="sb-card sb-card-wide" aria-labelledby="sb-connection-title">
        <header class="sb-card-header">
          <h2 id="sb-connection-title">连接状态</h2>
          <div class="sb-header-actions">
            <span class="sb-pill" :class="{ 'sb-pill-ok': hasConnection }">
              <span class="sb-pill-dot" />{{ hasConnection ? 'SSH 已连接' : '等待连接' }}
            </span>
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
          </div>
        </header>
        <div class="sb-connection">
          <div class="sb-connection-icon">
            <AppIcon name="secure-browser" :size="30" themed />
          </div>
          <div class="sb-connection-identity">
            <h3>安全浏览器</h3>
            <div class="sb-connection-meta sb-muted">{{ connectionText }}</div>
          </div>
          <span class="sb-pill sb-pill-desktop" :class="{ 'sb-pill-ok': hasConnection }">
            <span class="sb-pill-dot" />{{ hasConnection ? '连接就绪' : '未连接' }}
          </span>
        </div>
      </section>

      <section class="sb-card sb-card-wide" aria-labelledby="sb-session-title">
        <header class="sb-card-header">
          <h2 id="sb-session-title">浏览会话</h2>
          <span class="sb-pill" :class="{ 'sb-pill-ok': activeTunnel }">
            <span class="sb-pill-dot" />{{ activeTunnel ? '运行中' : '未启动' }}
          </span>
        </header>
        <div class="sb-session">
          <div class="sb-session-info">
            <div class="sb-session-icon" :class="{ 'sb-session-icon-active': activeTunnel }">
              <AppWindow :size="22" aria-hidden="true" />
            </div>
            <div class="sb-session-text">
              <strong>{{ activeTunnel ? '浏览器已准备好' : '准备启动' }}</strong>
              <small class="sb-muted">
                {{
                  activeTunnel
                    ? `代理 ${activeTunnel.bindHost}:${activeTunnel.bindPort}`
                    : '启动后将打开独立浏览器窗口'
                }}
              </small>
            </div>
          </div>
          <div class="sb-session-actions">
            <NButton
              v-if="activeTunnel"
              secondary
              type="error"
              :loading="operatingId === activeTunnel.id"
              @click="stopTunnel(activeTunnel)"
            >
              停止会话
            </NButton>
            <NButton
              type="primary"
              :disabled="!canLaunch"
              :loading="starting"
              @click="startSecureBrowser"
            >
              <template #icon><Play :size="15" /></template>
              {{ activeTunnel ? '打开浏览器' : '启动浏览器' }}
            </NButton>
          </div>
        </div>
        <dl class="sb-details">
          <div>
            <dt class="sb-muted">代理协议</dt>
            <dd>SOCKS5 over SSH</dd>
          </div>
          <div>
            <dt class="sb-muted">启动方式</dt>
            <dd>{{ launchModeText }}</dd>
          </div>
          <div v-if="activeTunnel">
            <dt class="sb-muted">启动时间</dt>
            <dd>{{ formatTime(activeTunnel.startedAt) }}</dd>
          </div>
          <div v-else>
            <dt class="sb-muted">代理端口</dt>
            <dd>启动时自动分配</dd>
          </div>
        </dl>
      </section>

      <section v-for="feature in features" :key="feature.title" class="sb-card">
        <header class="sb-card-header">
          <h2>{{ feature.title }}</h2>
        </header>
        <div class="sb-feature">
          <div class="sb-feature-icon">
            <component :is="feature.icon" :size="18" aria-hidden="true" />
          </div>
          <p class="sb-feature-desc sb-muted">{{ feature.desc }}</p>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.secure-browser-view {
  --sb-border: rgba(148, 163, 184, 0.2);
  --sb-surface: rgba(255, 255, 255, 0.72);
  --sb-header: rgba(148, 163, 184, 0.06);
  --sb-muted: #64748b;
  --sb-ok: #15803d;
  height: 100%;
  overflow: auto;
  padding: 20px;
  background:
    radial-gradient(circle at top left, rgba(56, 189, 248, 0.16), transparent 30%),
    radial-gradient(circle at top right, rgba(129, 140, 248, 0.14), transparent 28%),
    linear-gradient(180deg, rgba(15, 23, 42, 0.1), rgba(15, 23, 42, 0.04));
}

.secure-browser-dark {
  --sb-border: rgba(148, 163, 184, 0.13);
  --sb-surface: rgba(30, 32, 42, 0.66);
  --sb-header: rgba(255, 255, 255, 0.025);
  --sb-muted: #a1a1aa;
  --sb-ok: #4ade80;
}

.sb-grid {
  display: grid;
  min-height: 100%;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  align-content: center;
  gap: 14px;
  container-type: inline-size;
}

.sb-muted {
  color: var(--sb-muted);
}

.sb-card {
  min-width: 0;
  overflow: hidden;
  border: 1px solid var(--sb-border);
  border-radius: var(--app-radius-card, 10px);
  background: var(--sb-surface);
  backdrop-filter: blur(16px);
}

.sb-card-wide {
  grid-column: 1 / -1;
}

.sb-card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  min-height: 45px;
  padding: 10px 18px;
  border-bottom: 1px solid var(--sb-border);
  background: var(--sb-header);
}

.sb-card-header h2 {
  margin: 0;
  font-size: 13px;
  font-weight: 650;
}

.sb-header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.sb-pill {
  display: inline-flex;
  flex-shrink: 0;
  align-items: center;
  gap: 7px;
  padding: 4px 10px;
  border-radius: 999px;
  color: var(--sb-muted);
  background: rgba(148, 163, 184, 0.12);
  font-size: 12px;
  white-space: nowrap;
}

.sb-pill-ok {
  color: var(--sb-ok);
  background: rgba(34, 197, 94, 0.1);
}

.sb-pill-dot {
  width: 7px;
  height: 7px;
  flex: none;
  border-radius: 999px;
  background: currentColor;
}

.sb-connection {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 20px;
}

.sb-connection-icon {
  display: grid;
  flex-shrink: 0;
  width: 52px;
  height: 52px;
  border-radius: 12px;
  place-items: center;
  background: var(--app-primary-soft, rgba(37, 99, 235, 0.16));
}

.sb-connection-identity {
  flex: 1;
  min-width: 0;
}

.sb-connection-identity h3 {
  margin: 0 0 8px;
  font-size: 18px;
  font-weight: 700;
}

.sb-connection-meta {
  overflow: hidden;
  font-size: 13px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sb-session {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 16px;
  padding: 20px;
}

.sb-session-info {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 14px;
}

.sb-session-icon {
  display: grid;
  flex-shrink: 0;
  width: 44px;
  height: 44px;
  border-radius: 50%;
  place-items: center;
  color: var(--sb-muted);
  background: rgba(148, 163, 184, 0.12);
}

.sb-session-icon-active {
  color: var(--sb-ok);
  background: rgba(34, 197, 94, 0.12);
}

.sb-session-text strong,
.sb-session-text small {
  display: block;
}

.sb-session-text strong {
  font-size: 14px;
  font-weight: 650;
}

.sb-session-text small {
  margin-top: 5px;
  font-size: 12px;
  font-variant-numeric: tabular-nums;
}

.sb-session-actions {
  display: flex;
  align-items: center;
  gap: 10px;
}

.sb-details {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 16px;
  margin: 0 20px;
  padding: 16px 0 20px;
  border-top: 1px solid var(--sb-border);
}

.sb-details dt {
  margin-bottom: 6px;
  font-size: 12px;
}

.sb-details dd {
  overflow: hidden;
  margin: 0;
  font-size: 13px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sb-feature {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 18px 20px 20px;
}

.sb-feature-icon {
  display: grid;
  flex-shrink: 0;
  width: 36px;
  height: 36px;
  border-radius: 50%;
  place-items: center;
  color: var(--app-primary-color, #2563eb);
  background: var(--app-primary-soft, rgba(37, 99, 235, 0.16));
}

.sb-feature-desc {
  margin: 0;
  font-size: 12px;
  line-height: 1.7;
}

@container (max-width: 640px) {
  .sb-grid {
    grid-template-columns: minmax(0, 1fr);
    align-content: start;
  }

  .sb-connection {
    flex-wrap: wrap;
  }

  .sb-pill-desktop {
    margin-left: 68px;
  }

  .sb-session {
    align-items: stretch;
    flex-direction: column;
  }

  .sb-session-actions {
    justify-content: flex-end;
  }

  .sb-details {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>

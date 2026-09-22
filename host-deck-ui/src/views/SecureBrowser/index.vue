<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Launch } from '@vicons/carbon'
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

onMounted(() => {
  void fetchTunnels()
  void fetchCapabilities()
})
</script>

<template>
  <div class="secure-browser-view" :class="{ 'is-dark': settingsStore.isDark }">
    <div class="launcher-shell">
      <header class="launcher-header">
        <div class="brand-lockup">
          <div class="brand-icon"><AppIcon name="secure-browser" :size="27" themed /></div>
          <div>
            <div class="brand-kicker">HOST DECK / PRIVATE ACCESS</div>
            <h1>安全浏览器</h1>
          </div>
        </div>
        <NButton
          quaternary
          circle
          :loading="loading"
          aria-label="刷新浏览器状态"
          @click="fetchTunnels"
        >
          ↻
        </NButton>
      </header>

      <main class="launcher-main">
        <section class="hero-copy">
          <div class="section-eyebrow">ISOLATED BROWSING SESSION</div>
          <h2>把远程网络<br /><span>带到你的桌面。</span></h2>
          <p class="hero-description">
            通过 SSH 隧道建立隔离浏览环境。浏览器不会复用普通会话，访问结束后可随时关闭代理。
          </p>

          <div class="connection-panel">
            <div class="connection-status" :class="{ connected: hasConnection }">
              <span class="status-dot"></span>
              <span>{{ hasConnection ? 'SSH 连接就绪' : '等待 SSH 连接' }}</span>
            </div>
            <div class="connection-address">{{ connectionText }}</div>
          </div>
        </section>

        <div class="hero-art" aria-hidden="true">
          <div class="orbit orbit-large"></div>
          <div class="orbit orbit-small"></div>
          <div class="browser-card">
            <div class="browser-toolbar">
              <span></span><span></span><span></span>
              <i></i>
            </div>
            <div class="browser-card-content">
              <div class="browser-card-icon">
                <AppIcon name="secure-browser" :size="48" themed />
              </div>
              <div class="browser-card-lines"><b></b><b></b><b></b></div>
            </div>
          </div>
          <div class="secure-badge">SECURE<span>SSH TUNNEL</span></div>
        </div>

        <div class="feature-strip">
          <div class="feature-item">
            <span class="feature-index">01</span>
            <div><strong>隔离环境</strong><small>独立浏览器配置</small></div>
          </div>
          <div class="feature-item">
            <span class="feature-index">02</span>
            <div><strong>安全代理</strong><small>流量经 SSH 转发</small></div>
          </div>
          <div class="feature-item">
            <span class="feature-index">03</span>
            <div><strong>单实例</strong><small>一个连接，一个会话</small></div>
          </div>
        </div>
      </main>

      <footer class="launcher-footer">
        <div class="launch-status">
          <span class="status-ring" :class="{ active: activeTunnel }"></span>
          <div>
            <strong>{{ activeTunnel ? '浏览器已准备好' : '准备启动' }}</strong>
            <small v-if="activeTunnel">
              代理 {{ activeTunnel.bindHost }}:{{ activeTunnel.bindPort }}
            </small>
            <small v-else>启动后将打开独立 Chrome 窗口</small>
          </div>
        </div>
        <div class="launch-actions">
          <NButton
            v-if="activeTunnel"
            quaternary
            type="error"
            :loading="operatingId === activeTunnel.id"
            @click="stopTunnel(activeTunnel)"
          >
            停止会话
          </NButton>
          <NButton
            class="launch-button"
            type="primary"
            size="large"
            :disabled="!canLaunch"
            :loading="starting"
            @click="startSecureBrowser"
          >
            <template #icon
              ><NIcon><Launch /></NIcon
            ></template>
            {{ activeTunnel ? '打开浏览器' : '启动浏览器' }}
            <span class="launch-arrow">↗</span>
          </NButton>
        </div>
      </footer>
    </div>
  </div>
</template>

<style scoped>
.secure-browser-view {
  position: relative;
  height: 100%;
  overflow: auto;
  padding: 20px;
  color: #152235;
  background: radial-gradient(circle at 80% 8%, rgba(34, 197, 94, 0.14), transparent 30%), #eef3f5;
}

.secure-browser-view::before {
  position: absolute;
  inset: 0;
  pointer-events: none;
  content: '';
  opacity: 0.32;
  background-image:
    linear-gradient(rgba(100, 116, 139, 0.07) 1px, transparent 1px),
    linear-gradient(90deg, rgba(100, 116, 139, 0.07) 1px, transparent 1px);
  background-size: 28px 28px;
}

.is-dark.secure-browser-view {
  color: #e7f0f0;
  background: radial-gradient(circle at 80% 8%, rgba(45, 212, 191, 0.14), transparent 30%), #07131c;
}

.launcher-shell {
  position: relative;
  z-index: 1;
  display: flex;
  min-height: 100%;
  flex-direction: column;
  overflow: hidden;
  border: 1px solid rgba(148, 163, 184, 0.25);
  border-radius: 24px;
  background: rgba(255, 255, 255, 0.7);
  box-shadow: 0 24px 70px rgba(15, 23, 42, 0.1);
  backdrop-filter: blur(18px);
}

.is-dark .launcher-shell {
  border-color: rgba(148, 163, 184, 0.18);
  background: rgba(13, 27, 36, 0.78);
  box-shadow: 0 24px 70px rgba(0, 0, 0, 0.26);
}

.launcher-header {
  display: flex;
  flex: 0 0 auto;
  align-items: center;
  justify-content: space-between;
  padding: 24px 28px 10px;
}

.brand-lockup,
.launch-status,
.launch-actions {
  display: flex;
  align-items: center;
}

.brand-lockup {
  gap: 12px;
}
.brand-icon {
  display: grid;
  width: 45px;
  height: 45px;
  place-items: center;
  border: 1px solid rgba(20, 184, 166, 0.25);
  border-radius: 14px;
  background: rgba(20, 184, 166, 0.12);
}
.brand-kicker,
.section-eyebrow {
  color: #0f9f91;
  font-size: 10px;
  font-weight: 800;
  letter-spacing: 0.17em;
}
.is-dark .brand-kicker,
.is-dark .section-eyebrow {
  color: #5eead4;
}
.brand-lockup h1 {
  margin: 2px 0 0;
  font-size: 17px;
  font-weight: 750;
  letter-spacing: -0.02em;
}

.launcher-main {
  display: grid;
  flex: 1 1 auto;
  grid-template-columns: minmax(260px, 0.95fr) minmax(260px, 1.05fr);
  align-items: center;
  gap: 12px;
  padding: 34px 48px 30px;
}
.hero-copy {
  max-width: 440px;
}
.hero-copy h2 {
  margin: 13px 0 16px;
  color: #102334;
  font-size: clamp(30px, 4vw, 48px);
  font-weight: 800;
  line-height: 1.08;
  letter-spacing: -0.055em;
}
.hero-copy h2 span {
  color: #0e9f91;
}
.is-dark .hero-copy h2 {
  color: #ecfdf5;
}
.is-dark .hero-copy h2 span {
  color: #5eead4;
}
.hero-description {
  max-width: 390px;
  margin: 0;
  color: #607184;
  font-size: 13px;
  line-height: 1.75;
}
.is-dark .hero-description {
  color: #96a9b2;
}

.connection-panel {
  width: min(100%, 350px);
  margin-top: 28px;
  padding: 12px 14px;
  border: 1px solid rgba(148, 163, 184, 0.23);
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.62);
}
.is-dark .connection-panel {
  background: rgba(3, 12, 18, 0.3);
}
.connection-status {
  display: flex;
  align-items: center;
  gap: 8px;
  color: #b7791f;
  font-size: 12px;
  font-weight: 700;
}
.connection-status.connected {
  color: #0e9f91;
}
.status-dot,
.status-ring {
  width: 7px;
  height: 7px;
  flex: 0 0 auto;
  border-radius: 50%;
  background: #e2a83f;
  box-shadow: 0 0 0 4px rgba(226, 168, 63, 0.12);
}
.connection-status.connected .status-dot {
  background: #10b981;
  box-shadow: 0 0 0 4px rgba(16, 185, 129, 0.13);
}
.connection-address {
  overflow: hidden;
  margin-top: 8px;
  color: #718096;
  font-family: monospace;
  font-size: 11px;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.is-dark .connection-address {
  color: #9aadb5;
}

.hero-art {
  position: relative;
  display: grid;
  min-height: 265px;
  place-items: center;
}
.orbit {
  position: absolute;
  border: 1px solid rgba(20, 184, 166, 0.2);
  border-radius: 50%;
  transform: rotate(-24deg);
}
.orbit-large {
  width: min(31vw, 330px);
  height: min(15vw, 160px);
}
.orbit-small {
  width: min(25vw, 270px);
  height: min(12vw, 130px);
  border-color: rgba(16, 185, 129, 0.16);
  transform: rotate(34deg);
}
.browser-card {
  position: relative;
  z-index: 1;
  width: min(100%, 290px);
  overflow: hidden;
  border: 1px solid rgba(255, 255, 255, 0.65);
  border-radius: 16px;
  background: rgba(245, 253, 252, 0.75);
  box-shadow:
    0 26px 45px rgba(30, 91, 94, 0.18),
    0 0 0 9px rgba(20, 184, 166, 0.06);
  transform: rotate(-5deg);
}
.is-dark .browser-card {
  border-color: rgba(148, 163, 184, 0.2);
  background: rgba(18, 43, 49, 0.82);
  box-shadow:
    0 26px 45px rgba(0, 0, 0, 0.28),
    0 0 0 9px rgba(45, 212, 191, 0.06);
}
.browser-toolbar {
  display: flex;
  align-items: center;
  gap: 5px;
  height: 25px;
  padding: 0 10px;
  border-bottom: 1px solid rgba(148, 163, 184, 0.16);
}
.browser-toolbar span {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: #7dd3c7;
}
.browser-toolbar i {
  width: 95px;
  height: 5px;
  margin-left: 12px;
  border-radius: 4px;
  background: rgba(100, 116, 139, 0.15);
}
.browser-card-content {
  display: flex;
  align-items: center;
  gap: 19px;
  padding: 42px 28px;
}
.browser-card-icon {
  display: grid;
  width: 76px;
  height: 76px;
  place-items: center;
  border-radius: 23px;
  background: rgba(20, 184, 166, 0.13);
}
.browser-card-lines {
  display: grid;
  gap: 8px;
}
.browser-card-lines b {
  display: block;
  width: 72px;
  height: 6px;
  border-radius: 5px;
  background: rgba(20, 184, 166, 0.2);
}
.browser-card-lines b:nth-child(2) {
  width: 52px;
  background: rgba(100, 116, 139, 0.16);
}
.browser-card-lines b:nth-child(3) {
  width: 64px;
  background: rgba(100, 116, 139, 0.12);
}
.secure-badge {
  position: absolute;
  right: 3%;
  bottom: 8%;
  display: grid;
  gap: 2px;
  padding: 8px 11px;
  border: 1px solid rgba(20, 184, 166, 0.25);
  border-radius: 8px;
  color: #0e9f91;
  background: rgba(231, 253, 249, 0.86);
  font-size: 9px;
  font-weight: 800;
  letter-spacing: 0.14em;
  transform: rotate(4deg);
}
.secure-badge span {
  color: #7b8b96;
  font-size: 7px;
  letter-spacing: 0.08em;
}
.is-dark .secure-badge {
  background: rgba(10, 42, 42, 0.9);
}

.feature-strip {
  grid-column: 1 / -1;
  display: flex;
  flex-wrap: wrap;
  gap: 10px 34px;
  padding-top: 12px;
  border-top: 1px solid rgba(148, 163, 184, 0.18);
}
.feature-item {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 135px;
}
.feature-index {
  color: #0e9f91;
  font-family: monospace;
  font-size: 10px;
  font-weight: 800;
}
.feature-item strong,
.feature-item small {
  display: block;
}
.feature-item strong {
  font-size: 11px;
}
.feature-item small {
  margin-top: 3px;
  color: #80909b;
  font-size: 10px;
}

.launcher-footer {
  display: flex;
  flex: 0 0 auto;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  margin: 0 28px 24px;
  padding: 17px 18px 17px 20px;
  border: 1px solid rgba(148, 163, 184, 0.22);
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.5);
}
.is-dark .launcher-footer {
  background: rgba(2, 12, 18, 0.28);
}
.launch-status {
  gap: 10px;
}
.status-ring {
  width: 9px;
  height: 9px;
  background: #94a3b8;
  box-shadow: 0 0 0 5px rgba(148, 163, 184, 0.12);
}
.status-ring.active {
  background: #10b981;
  box-shadow: 0 0 0 5px rgba(16, 185, 129, 0.13);
}
.launch-status strong,
.launch-status small {
  display: block;
}
.launch-status strong {
  font-size: 12px;
}
.launch-status small {
  margin-top: 4px;
  color: #7b8b96;
  font-family: monospace;
  font-size: 10px;
}
.launch-actions {
  gap: 12px;
}
.launch-button {
  min-width: 178px;
  border-radius: 10px;
  font-weight: 750;
  box-shadow: 0 9px 20px rgba(13, 148, 136, 0.2);
}
.launch-arrow {
  margin-left: 10px;
  font-size: 16px;
  line-height: 1;
}

@media (max-width: 760px) {
  .secure-browser-view {
    padding: 10px;
  }
  .launcher-header {
    padding: 18px 18px 8px;
  }
  .launcher-main {
    grid-template-columns: 1fr;
    padding: 24px 24px 22px;
  }
  .hero-art {
    min-height: 205px;
  }
  .orbit-large {
    width: 300px;
    height: 145px;
  }
  .orbit-small {
    width: 240px;
    height: 115px;
  }
  .feature-strip {
    gap: 14px;
  }
  .launcher-footer {
    align-items: stretch;
    flex-direction: column;
    margin: 0 18px 18px;
  }
  .launch-actions {
    justify-content: flex-end;
  }
}

@media (min-width: 761px) and (max-height: 700px) {
  .secure-browser-view {
    padding: 12px 16px;
  }
  .launcher-header {
    padding: 16px 24px 6px;
  }
  .launcher-main {
    padding: 18px 36px 14px;
  }
  .hero-copy h2 {
    margin: 9px 0 11px;
    font-size: clamp(30px, 3.5vw, 40px);
  }
  .hero-description {
    line-height: 1.55;
  }
  .connection-panel {
    margin-top: 16px;
    padding: 10px 12px;
  }
  .hero-art {
    min-height: 190px;
  }
  .browser-card {
    width: min(100%, 270px);
  }
  .browser-card-content {
    padding: 30px 24px;
  }
  .browser-card-icon {
    width: 64px;
    height: 64px;
  }
  .feature-strip {
    gap: 8px 28px;
    padding-top: 9px;
  }
  .launcher-footer {
    margin: 0 24px 14px;
    padding: 12px 14px 12px 16px;
  }
}

@media (max-width: 430px) {
  .hero-copy h2 {
    font-size: 34px;
  }
  .browser-card {
    width: 250px;
  }
  .feature-item {
    min-width: 120px;
  }
  .launch-actions {
    align-items: stretch;
    flex-direction: column-reverse;
  }
  .launch-button {
    width: 100%;
  }
}

.secure-browser-view::-webkit-scrollbar {
  width: 0;
  height: 0;
  display: none;
}
</style>

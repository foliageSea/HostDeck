<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useMutation } from '@tanstack/vue-query'
import { ServerProxy } from '@vicons/carbon'
import { authApi, type ConnectParams, type ConnectResponse } from '@/api/auth'
import type { SavedServer } from '@/api/server'
import { createWallpaperStyle } from '@/lib/wallpapers'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

const sshStore = useSshStore()
const settingsStore = useSettingsStore()
const isEditing = ref(false)
const isNewServer = ref(false)
const isShaking = ref(false)
const selectedServerId = ref<number | null>(null)

const form = reactive({
  host: '',
  name: '',
  password: '',
  port: 22,
  privateKey: '',
  username: '',
})

const selectedServer = computed(() =>
  sshStore.savedServers.find((server) => server.id === selectedServerId.value) ?? null,
)
const loginWallpaperStyle = computed(() =>
  createWallpaperStyle('login', settingsStore.loginWallpaper, settingsStore.isDark),
)

function applyServer(server: SavedServer) {
  isEditing.value = true
  isNewServer.value = false
  selectedServerId.value = server.id ?? null
  form.host = server.host
  form.name = server.name
  form.password = server.password ?? ''
  form.port = server.port
  form.privateKey = server.privateKey ?? ''
  form.username = server.username
}

function createServer() {
  isEditing.value = true
  isNewServer.value = true
  resetForm(false)
}

function resetForm(resetEditing = true) {
  if (resetEditing) {
    isEditing.value = false
    isNewServer.value = false
  }

  selectedServerId.value = null
  form.host = ''
  form.name = ''
  form.password = ''
  form.port = 22
  form.privateKey = ''
  form.username = ''
}

const connectMutation = useMutation<ConnectResponse, Error, ConnectParams>({
  mutationFn: authApi.connect,
  onSuccess: (data) => {
    if (isNewServer.value) {
      void saveServerMutation.mutateAsync()
    }

    sshStore.setSession(data.sessionId, data.connectionId, form.host, form.username)
  },
  onError: (error) => {
    isShaking.value = true
    window.setTimeout(() => {
      isShaking.value = false
    }, 500)

    getUiApi().message.error(error.message || '连接失败')
  },
})

const saveServerMutation = useMutation<SavedServer | void, Error, void>({
  mutationFn: async () => {
    const payload = {
      host: form.host,
      name: form.name || `${form.username}@${form.host}`,
      password: form.password || undefined,
      port: form.port,
      privateKey: form.privateKey || undefined,
      username: form.username,
    }

    if (selectedServerId.value !== null && !isNewServer.value) {
      await sshStore.updateServer(selectedServerId.value, payload)
      return
    }

    return sshStore.addServer(payload)
  },
  onSuccess: () => {
    getUiApi().message.success(isNewServer.value ? '服务器已保存。' : '服务器配置已更新。')
    isNewServer.value = false
    isEditing.value = false
  },
  onError: (error) => {
    getUiApi().message.error(error.message || '保存服务器失败')
  },
})

const isConnecting = computed(() => connectMutation.isPending.value)
const isSavingServer = computed(() => saveServerMutation.isPending.value)

function handleConnect() {
  connectMutation.mutate({
    host: form.host,
    password: form.password || undefined,
    port: form.port,
    privateKey: form.privateKey || undefined,
    username: form.username,
  })
}

function handleSaveServer() {
  void saveServerMutation.mutateAsync()
}

async function handleDeleteServer(serverId?: number) {
  if (serverId === undefined) {
    return
  }

  await sshStore.removeServer(serverId)
  if (selectedServerId.value === serverId) {
    resetForm()
  }

  getUiApi().message.success('服务器配置已删除。')
}

onMounted(() => {
  void sshStore.fetchServers()
})
</script>

<template>
  <div class="login-screen">
    <div class="login-overlay" :style="loginWallpaperStyle" />
    <div class="login-layout">
      <section class="login-panel hero-panel">
        <div class="hero-badge">
          <NIcon :size="26">
            <ServerProxy />
          </NIcon>
          <span>ssh-tool-ui-next</span>
        </div>
        <h1>桌面式 SSH 工作台</h1>
        <p>集中管理连接、监控、终端与文件操作，在统一桌面界面中完成常用远程运维流程。</p>
        <div class="hero-meta">
          <span>Naive UI</span>
          <span>Pinia</span>
          <span>Vue Query</span>
          <span>Desktop Shell</span>
        </div>
      </section>

      <section class="login-panel form-panel" :class="{ 'form-panel-shake': isShaking }">
        <div class="panel-header">
          <div>
            <h2>连接服务器</h2>
            <p>支持保存、编辑和快速复用服务器连接配置。</p>
          </div>
          <NSpace>
            <NButton text @click="createServer">新建</NButton>
            <NButton text @click="resetForm">清空</NButton>
          </NSpace>
        </div>

        <div class="saved-servers">
          <div class="saved-servers-header">
            <span>已保存服务器</span>
            <NButton text @click="sshStore.fetchServers">刷新</NButton>
          </div>

          <NEmpty v-if="sshStore.savedServers.length === 0" description="暂无已保存服务器" size="small" />

          <NSpace v-else vertical :size="12">
            <NCard
              v-for="server in sshStore.savedServers"
              :key="server.id ?? `${server.host}-${server.port}`"
              size="small"
              embedded
              class="server-card"
              :class="{ 'server-card-active': selectedServer?.id === server.id }"
              @click="applyServer(server)"
            >
              <div class="server-card-content">
                <div>
                  <div class="server-name">{{ server.name || server.host }}</div>
                  <div class="server-desc">{{ server.username }}@{{ server.host }}:{{ server.port }}</div>
                </div>
                <NPopconfirm @positive-click="handleDeleteServer(server.id)">
                  <template #trigger>
                    <NButton quaternary type="error" size="small" @click.stop>
                      删除
                    </NButton>
                  </template>
                  删除该服务器配置？
                </NPopconfirm>
              </div>
            </NCard>
          </NSpace>
        </div>

        <NForm label-placement="top" :model="form" @submit.prevent="handleConnect">
          <NFormItem label="名称" path="name">
            <NInput v-model:value="form.name" placeholder="我的服务器" />
          </NFormItem>

          <NGrid :cols="2" :x-gap="12">
            <NFormItemGi label="主机" path="host">
              <NInput v-model:value="form.host" placeholder="127.0.0.1" />
            </NFormItemGi>
            <NFormItemGi label="端口" path="port">
              <NInputNumber v-model:value="form.port" :min="1" :max="65535" class="full-width" />
            </NFormItemGi>
          </NGrid>

          <NGrid :cols="2" :x-gap="12">
            <NFormItemGi label="用户名" path="username">
              <NInput v-model:value="form.username" placeholder="root" />
            </NFormItemGi>
            <NFormItemGi label="密码" path="password">
              <NInput v-model:value="form.password" type="password" show-password-on="click" placeholder="可选" />
            </NFormItemGi>
          </NGrid>

          <NFormItem label="私钥" path="privateKey">
            <NInput
              v-model:value="form.privateKey"
              type="textarea"
              :rows="4"
              placeholder="-----BEGIN OPENSSH PRIVATE KEY-----"
            />
          </NFormItem>

          <NSpace vertical :size="12">
            <NButton
              v-if="isEditing || selectedServerId !== null"
              secondary
              block
              size="large"
              :loading="isSavingServer"
              :disabled="!form.host || !form.username"
              @click="handleSaveServer"
            >
              {{ isNewServer ? '保存服务器配置' : '更新服务器配置' }}
            </NButton>

            <NButton
              attr-type="submit"
              type="primary"
              block
              size="large"
              :loading="isConnecting"
              :disabled="!form.host || !form.username"
            >
              连接并进入桌面
            </NButton>
          </NSpace>
        </NForm>
      </section>
    </div>
  </div>
</template>

<style scoped>
.login-screen {
  min-height: 100vh;
  position: relative;
  overflow: hidden;
}

.login-overlay {
  position: absolute;
  inset: 0;
  background-position: center;
  background-repeat: no-repeat;
  background-size: cover;
}

.login-layout {
  position: relative;
  z-index: 1;
  min-height: 100vh;
  display: grid;
  grid-template-columns: minmax(320px, 1.1fr) minmax(360px, 520px);
  gap: 24px;
  align-items: center;
  padding: 40px;
}

.login-panel {
  border: 1px solid rgba(148, 163, 184, 0.18);
  background: rgba(15, 23, 42, 0.58);
  backdrop-filter: blur(18px);
  border-radius: 24px;
  box-shadow: 0 24px 70px rgba(15, 23, 42, 0.35);
}

.hero-panel {
  padding: 40px;
}

.hero-panel h1 {
  margin: 20px 0 12px;
  font-size: clamp(2rem, 5vw, 3.75rem);
  line-height: 1.02;
  color: #f8fafc;
}

.hero-panel p {
  max-width: 600px;
  font-size: 1rem;
  color: rgba(226, 232, 240, 0.76);
}

.hero-badge {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  border-radius: 999px;
  background: rgba(15, 23, 42, 0.48);
  color: #cbd5e1;
}

.hero-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-top: 28px;
}

.hero-meta span {
  padding: 8px 12px;
  border-radius: 999px;
  background: rgba(59, 130, 246, 0.14);
  border: 1px solid rgba(96, 165, 250, 0.24);
  color: #bfdbfe;
  font-size: 0.92rem;
}

.form-panel {
  padding: 24px;
}

.form-panel-shake {
  animation: panel-shake 0.5s cubic-bezier(.36, .07, .19, .97) both;
}

.panel-header {
  display: flex;
  align-items: start;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 18px;
}

.panel-header h2 {
  margin: 0 0 4px;
  color: #f8fafc;
}

.panel-header p {
  margin: 0;
  color: rgba(226, 232, 240, 0.65);
  font-size: 0.92rem;
}

.saved-servers {
  margin-bottom: 18px;
}

.saved-servers-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 12px;
  color: rgba(226, 232, 240, 0.78);
  font-size: 0.92rem;
}

.server-card {
  cursor: pointer;
  transition: transform 0.18s ease, border-color 0.18s ease, background-color 0.18s ease;
}

.server-card:hover {
  transform: translateY(-1px);
}

.server-card-active {
  border-color: rgba(96, 165, 250, 0.52);
  background: rgba(30, 41, 59, 0.78);
}

.server-card-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 16px;
}

.server-name {
  color: #f8fafc;
  font-weight: 600;
}

.server-desc {
  color: rgba(203, 213, 225, 0.68);
  font-size: 0.85rem;
}

.full-width {
  width: 100%;
}

@keyframes panel-shake {
  0%,
  100% {
    transform: translateX(0);
  }

  20%,
  60% {
    transform: translateX(-5px);
  }

  40%,
  80% {
    transform: translateX(5px);
  }
}

@media (max-width: 960px) {
  .login-layout {
    grid-template-columns: 1fr;
    padding: 20px;
  }

  .hero-panel,
  .form-panel {
    padding: 24px;
  }
}
</style>

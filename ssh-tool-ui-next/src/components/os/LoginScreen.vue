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
  <div class="relative min-h-screen overflow-hidden">
    <div class="absolute inset-0 bg-cover bg-center bg-no-repeat" :style="loginWallpaperStyle" />
    <div class="relative z-1 grid min-h-screen grid-cols-[minmax(320px,1.1fr)_minmax(360px,520px)] items-center gap-[24px] p-[40px] lt-lg:grid-cols-1 lt-lg:p-[20px]">
      <section
        class="rounded-[24px] p-[40px] backdrop-blur-[18px] lt-lg:p-[24px]"
        :class="settingsStore.isDark ? 'glass-panel-dark' : 'glass-panel-light'"
      >
        <div
          class="inline-flex items-center gap-[10px] rounded-full px-[14px] py-[10px]"
          :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.48)] text-[#cbd5e1]' : 'bg-[rgba(255,255,255,0.7)] text-[#334155]'"
        >
          <NIcon :size="26">
            <ServerProxy />
          </NIcon>
          <span>ssh-tool-ui-next</span>
        </div>
        <h1 class="mb-[12px] mt-[20px] text-[clamp(2rem,5vw,3.75rem)] leading-[1.02]" :class="settingsStore.isDark ? 'text-[#f8fafc]' : 'text-[#0f172a]'">桌面式 SSH 工作台</h1>
        <p class="max-w-[600px] text-[1rem]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.76)]' : 'text-[rgba(51,65,85,0.8)]'">集中管理连接、监控、终端与文件操作，在统一桌面界面中完成常用远程运维流程。</p>
        <div class="mt-[28px] flex flex-wrap gap-[10px]">
          <span class="rounded-full border px-[12px] py-[8px] text-[0.92rem]" :class="settingsStore.isDark ? 'border-[rgba(96,165,250,0.24)] bg-[rgba(59,130,246,0.14)] text-[#bfdbfe]' : 'border-[rgba(96,165,250,0.28)] bg-[rgba(219,234,254,0.78)] text-[#1d4ed8]'">Naive UI</span>
          <span class="rounded-full border px-[12px] py-[8px] text-[0.92rem]" :class="settingsStore.isDark ? 'border-[rgba(96,165,250,0.24)] bg-[rgba(59,130,246,0.14)] text-[#bfdbfe]' : 'border-[rgba(96,165,250,0.28)] bg-[rgba(219,234,254,0.78)] text-[#1d4ed8]'">Pinia</span>
          <span class="rounded-full border px-[12px] py-[8px] text-[0.92rem]" :class="settingsStore.isDark ? 'border-[rgba(96,165,250,0.24)] bg-[rgba(59,130,246,0.14)] text-[#bfdbfe]' : 'border-[rgba(96,165,250,0.28)] bg-[rgba(219,234,254,0.78)] text-[#1d4ed8]'">Vue Query</span>
          <span class="rounded-full border px-[12px] py-[8px] text-[0.92rem]" :class="settingsStore.isDark ? 'border-[rgba(96,165,250,0.24)] bg-[rgba(59,130,246,0.14)] text-[#bfdbfe]' : 'border-[rgba(96,165,250,0.28)] bg-[rgba(219,234,254,0.78)] text-[#1d4ed8]'">Desktop Shell</span>
        </div>
      </section>

      <section
        class="rounded-[24px] p-[24px] backdrop-blur-[18px]"
        :class="[
          settingsStore.isDark ? 'glass-panel-dark' : 'glass-panel-light',
          { 'form-panel-shake': isShaking },
        ]"
      >
        <div class="mb-[18px] flex items-start justify-between gap-[12px]">
          <div>
            <h2 class="mb-[4px] mt-0" :class="settingsStore.isDark ? 'text-[#f8fafc]' : 'text-[#0f172a]'">连接服务器</h2>
            <p class="m-0 text-[0.92rem]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.65)]' : 'text-[rgba(51,65,85,0.8)]'">支持保存、编辑和快速复用服务器连接配置。</p>
          </div>
          <NSpace>
            <NButton text @click="createServer">新建</NButton>
            <NButton text @click="resetForm">清空</NButton>
          </NSpace>
        </div>

        <div class="mb-[18px]">
          <div class="mb-[12px] flex items-center justify-between text-[0.92rem]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.78)]' : 'text-[rgba(51,65,85,0.8)]'">
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
              class="cursor-pointer transition-[transform,border-color,background-color] duration-[180ms] ease-in-out hover:translate-y-[-1px]"
              :class="{
                'border-[rgba(96,165,250,0.52)] bg-[rgba(30,41,59,0.78)]': selectedServer?.id === server.id && settingsStore.isDark,
                'border-[rgba(59,130,246,0.38)] bg-[rgba(219,234,254,0.6)]': selectedServer?.id === server.id && !settingsStore.isDark,
              }"
              @click="applyServer(server)"
            >
              <div class="flex items-center justify-between gap-[16px]">
                <div>
                  <div class="font-600" :class="settingsStore.isDark ? 'text-[#f8fafc]' : 'text-[#0f172a]'">{{ server.name || server.host }}</div>
                  <div class="text-[0.85rem]" :class="settingsStore.isDark ? 'text-[rgba(203,213,225,0.68)]' : 'text-[rgba(51,65,85,0.8)]'">{{ server.username }}@{{ server.host }}:{{ server.port }}</div>
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
              <NInputNumber v-model:value="form.port" :min="1" :max="65535" class="w-full" />
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
.form-panel-shake {
  animation: panel-shake 0.5s cubic-bezier(.36, .07, .19, .97) both;
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

</style>

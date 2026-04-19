<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useMutation } from '@tanstack/vue-query'
import { authApi, type ConnectParams, type ConnectResponse } from '@/api/auth'
import type { SavedServer } from '@/api/server'
import { createWallpaperStyle } from '@/lib/wallpapers'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

type ServerFormState = {
  host: string
  name: string
  password: string
  port: number
  privateKey: string
  username: string
}

type ConnectionFormState = Omit<ServerFormState, 'name'>

const sshStore = useSshStore()
const settingsStore = useSettingsStore()
const isShaking = ref(false)
const selectedServerId = ref<number | null>(null)
const deletingServerId = ref<number | null>(null)
const serverEditorVisible = ref(false)
const editingServerId = ref<number | null>(null)
const serverEditorMode = ref<'create' | 'edit'>('create')

const connectionForm = reactive<ConnectionFormState>({
  host: '',
  password: '',
  port: 22,
  privateKey: '',
  username: '',
})

const serverForm = reactive<ServerFormState>({
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
  createWallpaperStyle('desktop', settingsStore.desktopWallpaper, settingsStore.isDark),
)
const serverEditorTitle = computed(() => (serverEditorMode.value === 'create' ? '新建服务器' : '编辑服务器'))

function applyConnectionForm(server: Pick<SavedServer, keyof ConnectionFormState>) {
  connectionForm.host = server.host
  connectionForm.password = server.password ?? ''
  connectionForm.port = server.port
  connectionForm.privateKey = server.privateKey ?? ''
  connectionForm.username = server.username
}

function applyServerForm(server: SavedServer) {
  serverForm.host = server.host
  serverForm.name = server.name
  serverForm.password = server.password ?? ''
  serverForm.port = server.port
  serverForm.privateKey = server.privateKey ?? ''
  serverForm.username = server.username
}

function applyServer(server: SavedServer) {
  selectedServerId.value = server.id ?? null
  applyConnectionForm(server)
}

function openCreateServerModal() {
  serverEditorMode.value = 'create'
  editingServerId.value = null
  resetServerForm()
  serverEditorVisible.value = true
}

function openEditServerModal(server: SavedServer) {
  serverEditorMode.value = 'edit'
  editingServerId.value = server.id ?? null
  applyServerForm(server)
  serverEditorVisible.value = true
}

function resetConnectionForm() {
  selectedServerId.value = null
  connectionForm.host = ''
  connectionForm.password = ''
  connectionForm.port = 22
  connectionForm.privateKey = ''
  connectionForm.username = ''
}

function resetServerForm() {
  serverForm.host = ''
  serverForm.name = ''
  serverForm.password = ''
  serverForm.port = 22
  serverForm.privateKey = ''
  serverForm.username = ''
}

const connectMutation = useMutation<ConnectResponse, Error, ConnectParams>({
  mutationFn: authApi.connect,
  onSuccess: (data) => {
    sshStore.setSession(
      data.sessionId,
      data.connectionId,
      connectionForm.host,
      connectionForm.port,
      connectionForm.username,
    )
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
      host: serverForm.host,
      name: serverForm.name || `${serverForm.username}@${serverForm.host}`,
      password: serverForm.password || undefined,
      port: serverForm.port,
      privateKey: serverForm.privateKey || undefined,
      username: serverForm.username,
    }

    if (editingServerId.value !== null && serverEditorMode.value === 'edit') {
      await sshStore.updateServer(editingServerId.value, payload)
      return
    }

    return sshStore.addServer(payload)
  },
  onSuccess: (savedServer) => {
    const isCreating = serverEditorMode.value === 'create'
    getUiApi().message.success(isCreating ? '服务器已保存。' : '服务器配置已更新。')

    if (isCreating && savedServer) {
      applyServer(savedServer)
    }

    if (!isCreating && editingServerId.value !== null && selectedServerId.value === editingServerId.value) {
      applyConnectionForm({
        host: serverForm.host,
        password: serverForm.password || undefined,
        port: serverForm.port,
        privateKey: serverForm.privateKey || undefined,
        username: serverForm.username,
      })
    }

    serverEditorVisible.value = false
    editingServerId.value = null
    resetServerForm()
  },
  onError: (error) => {
    getUiApi().message.error(error.message || '保存服务器失败')
  },
})

const isConnecting = computed(() => connectMutation.isPending.value)
const isSavingServer = computed(() => saveServerMutation.isPending.value)

function handleConnect() {
  connectMutation.mutate({
    host: connectionForm.host,
    password: connectionForm.password || undefined,
    port: connectionForm.port,
    privateKey: connectionForm.privateKey || undefined,
    username: connectionForm.username,
  })
}

function handleSaveServer() {
  void saveServerMutation.mutateAsync()
}

function handleCloseServerEditor() {
  serverEditorVisible.value = false
  editingServerId.value = null
  resetServerForm()
}

async function handleDeleteServer(serverId?: number) {
  if (serverId === undefined || deletingServerId.value === serverId) {
    return
  }

  deletingServerId.value = serverId
  try {
    await sshStore.removeServer(serverId)
    if (selectedServerId.value === serverId) {
      resetConnectionForm()
    }

    if (editingServerId.value === serverId) {
      handleCloseServerEditor()
    }

    getUiApi().message.success('服务器配置已删除。')
  } catch (error) {
    console.error('Failed to delete saved server', error)
    getUiApi().message.error(error instanceof Error ? error.message : '删除服务器配置失败。')
  } finally {
    deletingServerId.value = null
  }
}

onMounted(() => {
  void sshStore.fetchServers()
})
</script>

<template>
  <div class="relative min-h-screen overflow-hidden">
    <div class="absolute inset-0 bg-cover bg-center bg-no-repeat" :style="loginWallpaperStyle" />
    <div class="relative z-1 grid min-h-screen place-items-center p-[40px] lt-lg:p-[20px]">
      <section
        class="w-full max-w-[520px] rounded-[24px] p-[24px] backdrop-blur-[18px]"
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
            <NButton text @click="openCreateServerModal">新建</NButton>
            <NButton text @click="resetConnectionForm">清空</NButton>
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
                <NSpace :size="8" @click.stop>
                  <NButton quaternary size="small" @click="openEditServerModal(server)">
                    编辑
                  </NButton>
                  <NPopconfirm :positive-button-props="{ loading: deletingServerId === server.id }"
                    @positive-click="handleDeleteServer(server.id)">
                    <template #trigger>
                      <NButton quaternary type="error" size="small">
                        删除
                      </NButton>
                    </template>
                    删除该服务器配置？
                  </NPopconfirm>
                </NSpace>
              </div>
            </NCard>
          </NSpace>
        </div>

        <NForm label-placement="top" :model="connectionForm" @submit.prevent="handleConnect">
          <NGrid :cols="2" :x-gap="12">
            <NFormItemGi label="主机" path="host">
              <NInput v-model:value="connectionForm.host" placeholder="127.0.0.1" />
            </NFormItemGi>
            <NFormItemGi label="端口" path="port">
              <NInputNumber v-model:value="connectionForm.port" :min="1" :max="65535" class="w-full" />
            </NFormItemGi>
          </NGrid>

          <NGrid :cols="2" :x-gap="12">
            <NFormItemGi label="用户名" path="username">
              <NInput v-model:value="connectionForm.username" placeholder="root" />
            </NFormItemGi>
            <NFormItemGi label="密码" path="password">
              <NInput v-model:value="connectionForm.password" type="password" show-password-on="click" placeholder="可选" />
            </NFormItemGi>
          </NGrid>

          <NFormItem label="私钥" path="privateKey">
            <NInput
              v-model:value="connectionForm.privateKey"
              type="textarea"
              :rows="4"
              placeholder="-----BEGIN OPENSSH PRIVATE KEY-----"
            />
          </NFormItem>

          <NSpace vertical :size="12">
            <NButton
              attr-type="submit"
              type="primary"
              block
              size="large"
              :loading="isConnecting"
              :disabled="!connectionForm.host || !connectionForm.username"
            >
              连接并进入桌面
            </NButton>
          </NSpace>
        </NForm>
      </section>

      <NModal v-model:show="serverEditorVisible" preset="card" :title="serverEditorTitle" style="width: min(560px, 92vw)">
        <NForm label-placement="top" :model="serverForm" @submit.prevent="handleSaveServer">
          <NFormItem label="名称" path="name">
            <NInput v-model:value="serverForm.name" placeholder="我的服务器" />
          </NFormItem>

          <NGrid :cols="2" :x-gap="12">
            <NFormItemGi label="主机" path="host">
              <NInput v-model:value="serverForm.host" placeholder="127.0.0.1" />
            </NFormItemGi>
            <NFormItemGi label="端口" path="port">
              <NInputNumber v-model:value="serverForm.port" :min="1" :max="65535" class="w-full" />
            </NFormItemGi>
          </NGrid>

          <NGrid :cols="2" :x-gap="12">
            <NFormItemGi label="用户名" path="username">
              <NInput v-model:value="serverForm.username" placeholder="root" />
            </NFormItemGi>
            <NFormItemGi label="密码" path="password">
              <NInput v-model:value="serverForm.password" type="password" show-password-on="click" placeholder="可选" />
            </NFormItemGi>
          </NGrid>

          <NFormItem label="私钥" path="privateKey">
            <NInput
              v-model:value="serverForm.privateKey"
              type="textarea"
              :rows="4"
              placeholder="-----BEGIN OPENSSH PRIVATE KEY-----"
            />
          </NFormItem>

          <div class="flex justify-end gap-[12px]">
            <NButton @click="handleCloseServerEditor">
              取消
            </NButton>
            <NButton
              attr-type="submit"
              type="primary"
              :loading="isSavingServer"
              :disabled="!serverForm.host || !serverForm.username"
            >
              {{ serverEditorMode === 'create' ? '保存服务器配置' : '更新服务器配置' }}
            </NButton>
          </div>
        </NForm>
      </NModal>
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

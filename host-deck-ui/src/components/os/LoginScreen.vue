<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useMutation } from '@tanstack/vue-query'
import { authApi, type ConnectParams, type ConnectResponse } from '@/api/auth'
import type { SavedServer } from '@/api/server'
import { createWallpaperFilter, createWallpaperStyle } from '@/lib/wallpapers'
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

const selectedServer = computed(
  () => sshStore.savedServers.find((server) => server.id === selectedServerId.value) ?? null,
)
const loginWallpaperStyle = computed(() =>
  createWallpaperStyle('desktop', settingsStore.desktopWallpaper, settingsStore.isDark),
)
const loginWallpaperFilter = computed(() => createWallpaperFilter(settingsStore.desktopWallpaper))
const isVideoWallpaper = computed(
  () =>
    settingsStore.desktopWallpaper.mode === 'custom' &&
    settingsStore.desktopWallpaper.customType === 'video' &&
    Boolean(settingsStore.desktopWallpaper.customDataUrl),
)
const loginVideoWallpaperUrl = computed(() => {
  const wallpaperUrl = settingsStore.desktopWallpaper.customDataUrl
  if (
    !wallpaperUrl ||
    !wallpaperUrl.startsWith('/') ||
    !import.meta.env.DEV ||
    !import.meta.env.VITE_DEV_PROXY_TARGET
  ) {
    return wallpaperUrl ?? undefined
  }

  try {
    return new URL(wallpaperUrl, import.meta.env.VITE_DEV_PROXY_TARGET).toString()
  } catch {
    return wallpaperUrl
  }
})
const serverEditorTitle = computed(() =>
  serverEditorMode.value === 'create' ? '新建服务器' : '编辑服务器',
)

function selectFirstAvailableServer() {
  const firstServer = sshStore.savedServers[0]
  if (firstServer) {
    applyServer(firstServer)
    return
  }

  resetConnectionForm()
}

function applyConnectionForm(server: Pick<SavedServer, keyof ConnectionFormState>) {
  connectionForm.host = server.host
  connectionForm.port = server.port
  connectionForm.username = server.username
}

function applyServerForm(server: SavedServer) {
  serverForm.host = server.host
  serverForm.name = server.name
  serverForm.password = ''
  serverForm.port = server.port
  serverForm.privateKey = ''
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
      data.connectionId,
      connectionForm.host,
      connectionForm.port,
      connectionForm.username,
      {
        serverId: selectedServer.value?.id,
        host: connectionForm.host,
        port: connectionForm.port,
        username: connectionForm.username,
      },
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
      port: serverForm.port,
      username: serverForm.username,
      ...(serverForm.password ? { password: serverForm.password } : {}),
      ...(serverForm.privateKey ? { privateKey: serverForm.privateKey } : {}),
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

    if (
      !isCreating &&
      editingServerId.value !== null &&
      selectedServerId.value === editingServerId.value
    ) {
      applyConnectionForm({
        host: serverForm.host,
        port: serverForm.port,
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

const testConnectionMutation = useMutation<{ success: boolean }, Error, ConnectParams>({
  mutationFn: authApi.testConnect,
  onSuccess: () => {
    getUiApi().message.success('连接测试成功！')
  },
  onError: (error) => {
    getUiApi().message.error(error.message || '连接测试失败')
  },
})

const isConnecting = computed(() => connectMutation.isPending.value)
const isSavingServer = computed(() => saveServerMutation.isPending.value)
const isTesting = computed(() => testConnectionMutation.isPending.value)
const canConnect = computed(
  () => Boolean(selectedServer.value?.id && connectionForm.host && connectionForm.username),
)

function handleConnect() {
  if (!selectedServer.value) {
    getUiApi().message.warning('请先选择一个服务器。')
    return
  }

  if (selectedServer.value.id === undefined) {
    getUiApi().message.warning('服务器配置尚未保存，请先保存后再连接。')
    return
  }

  connectMutation.mutate({
    serverId: selectedServer.value.id,
    host: connectionForm.host,
    port: connectionForm.port,
    username: connectionForm.username,
  })
}

function handleTestConnection() {
  const hasSecretInput = Boolean(serverForm.password || serverForm.privateKey)
  testConnectionMutation.mutate({
    ...(!hasSecretInput && serverEditorMode.value === 'edit' && editingServerId.value !== null
      ? { serverId: editingServerId.value }
      : {}),
    host: serverForm.host,
    password: serverForm.password || undefined,
    port: serverForm.port,
    privateKey: serverForm.privateKey || undefined,
    username: serverForm.username,
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
      const nextServer = sshStore.savedServers.find((server) => server.id !== serverId)
      if (nextServer) {
        applyServer(nextServer)
      } else {
        resetConnectionForm()
      }
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

onMounted(async () => {
  await sshStore.fetchServers()
  if (!selectedServer.value) {
    selectFirstAvailableServer()
  }
})
</script>

<template>
  <div class="relative min-h-screen overflow-hidden">
    <video
      v-if="isVideoWallpaper"
      class="absolute inset-0 h-full w-full object-cover"
      :src="loginVideoWallpaperUrl"
      :style="{ filter: loginWallpaperFilter }"
      autoplay
      muted
      loop
      playsinline
    />
    <div
      v-else
      class="absolute inset-0 bg-cover bg-center bg-no-repeat"
      :style="loginWallpaperStyle"
    />
    <div class="relative z-1 grid min-h-screen place-items-center p-[40px] lt-lg:p-[20px]">
      <section
        class="app-radius-card w-full max-w-[520px] rounded-[24px] p-[24px] backdrop-blur-[18px]"
        :class="[
          settingsStore.isDark ? 'glass-panel-dark' : 'glass-panel-light',
          { 'form-panel-shake': isShaking },
        ]"
      >
        <div class="mb-[22px] flex items-center justify-between gap-[16px]">
          <div class="flex min-w-0 items-center gap-[12px]">
            <div class="login-brand-icon flex-none" aria-hidden="true">
              <img src="/favicon.png" alt="" />
            </div>
            <h2
              class="m-0 truncate"
              :class="settingsStore.isDark ? 'text-[#f8fafc]' : 'text-[#0f172a]'"
            >
              选择主机登录
            </h2>
          </div>
          <NSpace :wrap="false" :size="10">
            <NButton text @click="openCreateServerModal">新建</NButton>
            <NButton text @click="sshStore.fetchServers">刷新</NButton>
          </NSpace>
        </div>

        <NEmpty v-if="sshStore.savedServers.length === 0" description="暂无服务器配置" size="large">
          <template #extra>
            <NButton type="primary" @click="openCreateServerModal">添加服务器</NButton>
          </template>
        </NEmpty>

        <template v-else>
          <div class="mb-[22px] flex max-h-[360px] flex-col gap-[10px] overflow-y-auto pr-[2px]">
            <div
              v-for="server in sshStore.savedServers"
              :key="server.id ?? `${server.host}-${server.port}`"
              class="app-radius-card group server-list-item flex cursor-pointer items-center justify-between gap-[12px] rounded-[18px] border border-transparent px-[16px] py-[13px] text-left transition-[transform,background-color,border-color,box-shadow] duration-[180ms] ease-in-out hover:translate-y-[-2px] lt-sm:items-start"
              :class="[
                settingsStore.isDark
                  ? 'bg-[rgba(15,23,42,0.34)] hover:bg-[rgba(30,41,59,0.62)]'
                  : 'bg-[rgba(255,255,255,0.46)] hover:bg-[rgba(255,255,255,0.78)]',
                { 'server-list-item-selected': server.id === selectedServerId },
              ]"
              @click="applyServer(server)"
            >
              <div class="min-w-0 flex-1">
                <div class="flex items-center justify-between gap-[12px]">
                  <div
                    class="truncate text-[0.98rem] font-600"
                    :class="settingsStore.isDark ? 'text-[#f8fafc]' : 'text-[#0f172a]'"
                  >
                    {{ server.name || server.host }}
                  </div>
                </div>
                <div
                  class="mt-[4px] truncate text-[0.82rem]"
                  :class="
                    settingsStore.isDark
                      ? 'text-[rgba(203,213,225,0.7)]'
                      : 'text-[rgba(51,65,85,0.76)]'
                  "
                >
                  {{ server.username }}@{{ server.host }}:{{ server.port }}
                </div>
              </div>
              <NSpace :size="8" :wrap="false" align="center" class="flex-none" @click.stop>
                <div
                  v-if="server.id === selectedServerId"
                  class="self-center rounded-full px-[8px] py-[2px] text-[0.72rem] font-600 text-[var(--app-primary-color)] selected-server-badge"
                >
                  已选择
                </div>
                <NButton quaternary size="small" @click="openEditServerModal(server)">
                  编辑
                </NButton>
                <NPopconfirm
                  :positive-button-props="{ loading: deletingServerId === server.id }"
                  @positive-click="handleDeleteServer(server.id)"
                >
                  <template #trigger>
                    <NButton
                      quaternary
                      type="error"
                      size="small"
                      :disabled="server.id === undefined"
                    >
                      删除
                    </NButton>
                  </template>
                  删除该服务器配置？
                </NPopconfirm>
              </NSpace>
            </div>
          </div>

          <form @submit.prevent="handleConnect">
            <NButton
              attr-type="submit"
              type="primary"
              block
              size="large"
              :loading="isConnecting"
              :disabled="!canConnect"
            >
              连接
            </NButton>
          </form>
        </template>
      </section>

      <NModal
        v-model:show="serverEditorVisible"
        preset="card"
        :title="serverEditorTitle"
        style="width: min(560px, 92vw)"
      >
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
              <NInput
                v-model:value="serverForm.password"
                type="password"
                show-password-on="click"
                :placeholder="
                  serverEditorMode === 'edit' ? '留空则保留已保存密码' : '可选'
                "
              />
            </NFormItemGi>
          </NGrid>

          <NFormItem label="私钥" path="privateKey">
            <NInput
              v-model:value="serverForm.privateKey"
              type="textarea"
              :rows="4"
              :placeholder="
                serverEditorMode === 'edit'
                  ? '留空则保留已保存私钥'
                  : '-----BEGIN OPENSSH PRIVATE KEY-----'
              "
            />
          </NFormItem>

          <div class="flex justify-end gap-[12px]">
            <NButton
              :loading="isTesting"
              :disabled="!serverForm.host || !serverForm.username"
              @click="handleTestConnection"
            >
              测试连接
            </NButton>
            <NButton @click="handleCloseServerEditor"> 取消 </NButton>
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
  animation: panel-shake 0.5s cubic-bezier(0.36, 0.07, 0.19, 0.97) both;
}

.server-list-item-selected {
  border-color: var(--app-primary-color);
  box-shadow: 0 12px 28px rgba(59, 130, 246, 0.18);
  background: color-mix(in srgb, var(--app-primary-color) 16%, transparent) !important;
}

.selected-server-badge {
  background: color-mix(in srgb, var(--app-primary-color) 14%, transparent);
}

.login-brand-icon {
  display: grid;
  width: 46px;
  height: 46px;
  place-items: center;
  border: 1px solid rgba(148, 163, 184, 0.2);
  border-radius: var(--app-radius-surface);
  background: rgba(255, 255, 255, 0.16);
  box-shadow: 0 14px 32px rgba(15, 23, 42, 0.16);
}

.login-brand-icon img {
  width: 30px;
  height: 30px;
  object-fit: contain;
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

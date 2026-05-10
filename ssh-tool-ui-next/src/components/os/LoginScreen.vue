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

const selectedServer = computed(() =>
  sshStore.savedServers.find((server) => server.id === selectedServerId.value) ?? null,
)
const loginWallpaperStyle = computed(() =>
  createWallpaperStyle('login', settingsStore.desktopWallpaper, settingsStore.isDark),
)
const loginWallpaperFilter = computed(() => createWallpaperFilter(settingsStore.desktopWallpaper))
const isVideoWallpaper = computed(() =>
  settingsStore.desktopWallpaper.mode === 'custom'
  && settingsStore.desktopWallpaper.customType === 'video'
  && Boolean(settingsStore.desktopWallpaper.customDataUrl),
)
const serverEditorTitle = computed(() => (serverEditorMode.value === 'create' ? '新建服务器' : '编辑服务器'))

function getServerAvatarText(server: SavedServer) {
  const source = server.username || server.name || server.host
  return source.trim().slice(0, 1).toUpperCase() || '?'
}

function getServerAvatarGradient(server: SavedServer) {
  const source = `${server.username}${server.id ?? ''}${server.host}${server.name}`
  let hash = 0
  for (let index = 0; index < source.length; index += 1) {
    hash = source.charCodeAt(index) + ((hash << 5) - hash)
  }

  const hue = Math.abs(hash) % 360
  return `linear-gradient(135deg, hsl(${hue} 82% 62%), hsl(${(hue + 42) % 360} 78% 48%))`
}

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
      data.connectionId,
      connectionForm.host,
      connectionForm.port,
      connectionForm.username,
      {
        host: connectionForm.host,
        password: connectionForm.password || undefined,
        port: connectionForm.port,
        privateKey: connectionForm.privateKey || undefined,
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
  if (!selectedServer.value) {
    getUiApi().message.warning('请先选择一个服务器。')
    return
  }

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
      :src="settingsStore.desktopWallpaper.customDataUrl ?? undefined"
      :style="{ filter: loginWallpaperFilter }"
      autoplay
      muted
      loop
      playsinline
    />
    <div v-else class="absolute inset-0 bg-cover bg-center bg-no-repeat" :style="loginWallpaperStyle" />
    <div class="relative z-1 grid min-h-screen place-items-center p-[40px] lt-lg:p-[20px]">
      <section
        class="w-full max-w-[520px] rounded-[24px] p-[24px] backdrop-blur-[18px]"
        :class="[
          settingsStore.isDark ? 'glass-panel-dark' : 'glass-panel-light',
          { 'form-panel-shake': isShaking },
        ]"
      >
        <div class="mb-[22px] flex items-center justify-between gap-[16px]">
          <div>
            <h2 class="mb-[4px] mt-0" :class="settingsStore.isDark ? 'text-[#f8fafc]' : 'text-[#0f172a]'">选择主机登录</h2>
          </div>
          <NSpace :wrap="false" :size="10">
            <NButton text @click="openCreateServerModal">新建</NButton>
            <NButton text @click="sshStore.fetchServers">刷新</NButton>
          </NSpace>
        </div>

        <NEmpty v-if="sshStore.savedServers.length === 0" description="暂无服务器头像" size="large">
          <template #extra>
            <NButton type="primary" @click="openCreateServerModal">添加服务器</NButton>
          </template>
        </NEmpty>

        <template v-else>
          <div class="mb-[22px] grid grid-cols-[repeat(auto-fit,minmax(118px,1fr))] gap-[14px]">
            <button
              v-for="server in sshStore.savedServers"
              :key="server.id ?? `${server.host}-${server.port}`"
              type="button"
              class="group rounded-[24px] border border-transparent px-[12px] py-[16px] text-center transition-[transform,border-color,background-color,box-shadow] duration-[180ms] ease-in-out hover:translate-y-[-3px]"
              :class="[
                selectedServer?.id === server.id
                  ? settingsStore.isDark
                    ? 'border-[rgba(147,197,253,0.86)] bg-[rgba(37,99,235,0.28)] shadow-[0_0_0_3px_rgba(96,165,250,0.2),0_22px_55px_rgba(15,23,42,0.42)]'
                    : 'border-[rgba(37,99,235,0.58)] bg-[rgba(219,234,254,0.86)] shadow-[0_0_0_3px_rgba(59,130,246,0.16),0_22px_55px_rgba(37,99,235,0.18)]'
                  : settingsStore.isDark
                    ? 'bg-[rgba(15,23,42,0.34)] hover:bg-[rgba(30,41,59,0.62)]'
                    : 'bg-[rgba(255,255,255,0.46)] hover:bg-[rgba(255,255,255,0.78)]',
              ]"
              @click="applyServer(server)"
            >
              <div class="mx-auto mb-[10px] grid h-[58px] w-[58px] place-items-center rounded-full shadow-[0_14px_28px_rgba(15,23,42,0.24)] transition-transform duration-[180ms] group-hover:scale-[1.05]">
                <div
                  class="grid h-full w-full place-items-center rounded-full text-[1.45rem] font-800 text-white"
                  :style="{ background: getServerAvatarGradient(server) }"
                >
                  {{ getServerAvatarText(server) }}
                </div>
              </div>
              <div class="truncate font-600" :class="settingsStore.isDark ? 'text-[#f8fafc]' : 'text-[#0f172a]'">
                {{ server.username }}
              </div>
              <div class="mt-[3px] truncate text-[0.78rem]" :class="settingsStore.isDark ? 'text-[rgba(203,213,225,0.68)]' : 'text-[rgba(51,65,85,0.76)]'">
                {{ server.name || server.host }}
              </div>
              <div class="mt-[3px] text-[0.72rem]" :class="settingsStore.isDark ? 'text-[rgba(203,213,225,0.5)]' : 'text-[rgba(51,65,85,0.58)]'">
                端口 {{ server.port }}
              </div>
            </button>
          </div>

          <div
            class="mb-[18px] rounded-[18px] p-[14px]"
            :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.38)]' : 'bg-[rgba(255,255,255,0.48)]'"
          >
            <div class="flex items-center justify-between gap-[12px]">
              <div class="min-w-0">
                <div class="text-[0.78rem]" :class="settingsStore.isDark ? 'text-[rgba(203,213,225,0.58)]' : 'text-[rgba(51,65,85,0.62)]'">当前登录</div>
                <div class="mt-[3px] truncate text-[1rem] font-600" :class="settingsStore.isDark ? 'text-[#f8fafc]' : 'text-[#0f172a]'">
                  {{ selectedServer?.name || selectedServer?.host }}
                </div>
                <div class="mt-[3px] truncate text-[0.85rem]" :class="settingsStore.isDark ? 'text-[rgba(203,213,225,0.72)]' : 'text-[rgba(51,65,85,0.78)]'">
                  {{ selectedServer?.username }}@{{ selectedServer?.host }}:{{ selectedServer?.port }}
                </div>
              </div>

              <NSpace :size="8" @click.stop>
                <NButton quaternary size="small" :disabled="!selectedServer" @click="selectedServer && openEditServerModal(selectedServer)">
                  编辑
                </NButton>
                <NPopconfirm
                  :positive-button-props="{ loading: deletingServerId === selectedServer?.id }"
                  @positive-click="handleDeleteServer(selectedServer?.id)"
                >
                  <template #trigger>
                    <NButton quaternary type="error" size="small" :disabled="!selectedServer">
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
              :disabled="!selectedServer || !connectionForm.host || !connectionForm.username"
            >
              连接
            </NButton>
          </form>
        </template>
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

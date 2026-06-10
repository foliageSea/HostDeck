<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { LogoDocker } from '@vicons/ionicons5'
import { dockerApi, type DockerCreateContainerPayload, type DockerImage } from '@/api/docker'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

const props = defineProps<{
  windowId?: string
  connectionId?: string
  host?: string
}>()

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const loadingImages = ref(false)
const loadingImageDefaults = ref(false)
const creatingContainer = ref(false)
const images = ref<DockerImage[]>([])
const createForm = ref<DockerCreateContainerPayload>({
  image: '',
  name: '',
  restartPolicy: 'no',
  start: true,
})
const createPortsText = ref('')
const createEnvText = ref('')
const createVolumesText = ref('')
const createCmdText = ref('')
const createEntrypointText = ref('')
let imageDefaultsRequestId = 0

const activeConnectionId = computed(() => props.connectionId ?? sshStore.connectionId)
const createImageOptions = computed(() =>
  images.value
    .filter((item) => item.repository && item.tag && !item.dangling)
    .map((item) => {
      const imageName = `${item.repository}:${item.tag}`
      return {
        label: item.inUse ? `${imageName} (使用中)` : imageName,
        value: imageName,
      }
    }),
)
const selectedImage = computed(() =>
  images.value.find((item) => `${item.repository}:${item.tag}` === createForm.value.image),
)

function requireConnectionId() {
  const connectionId = activeConnectionId.value
  if (!connectionId) {
    throw new Error('当前没有可用的 Docker 连接。')
  }

  return connectionId
}

function toLineList(value: string) {
  return value
    .split(/\r?\n/)
    .map((item) => item.trim())
    .filter(Boolean)
}

function setTextIfChanged(target: { value: string }, lines: string[]) {
  const nextValue = lines.join('\n')
  if (target.value !== nextValue) {
    target.value = nextValue
  }
}

function sanitizePathSegment(value: string) {
  return (
    value
      .trim()
      .replace(/^[a-z]+:\/\//i, '')
      .replace(/[^a-zA-Z0-9._-]+/g, '-')
      .replace(/^-+|-+$/g, '') || 'container'
  )
}

function getImageVolumeDefaults(image: DockerImage, volumes: string[]) {
  const imageName = `${image.repository}:${image.tag}`
  const imageSegment = sanitizePathSegment(imageName)
  const basePath = `/opt/docker-volumes/${imageSegment}`

  return volumes.map((volume) => {
    if (volume.includes(':')) {
      return volume
    }

    const containerPath = volume.startsWith('/') ? volume : `/${volume}`
    const hostPath = `${basePath}${containerPath}`.replace(/\/+/g, '/')
    return `${hostPath}:${containerPath}`
  })
}

function closeWindow() {
  if (props.windowId) {
    desktopStore.closeWindow(props.windowId)
  }
}

async function loadImages() {
  loadingImages.value = true
  try {
    const connectionId = requireConnectionId()
    const result = await dockerApi.listImages(connectionId, { page: 1, pageSize: 100 })
    images.value = result.items
  } catch (error) {
    console.error('Failed to load Docker images', error)
    getUiApi().message.error(error instanceof Error ? error.message : '加载镜像列表失败。')
  } finally {
    loadingImages.value = false
  }
}

async function loadImageDefaults(image: DockerImage | undefined) {
  const requestId = ++imageDefaultsRequestId
  if (!image || !image.id) {
    setTextIfChanged(createPortsText, [])
    setTextIfChanged(createVolumesText, [])
    return
  }

  loadingImageDefaults.value = true
  try {
    const connectionId = requireConnectionId()
    const defaults = await dockerApi.getImageCreateDefaults(connectionId, image.id)
    if (requestId !== imageDefaultsRequestId) {
      return
    }

    setTextIfChanged(createPortsText, defaults.ports)
    setTextIfChanged(createVolumesText, getImageVolumeDefaults(image, defaults.volumes))
  } catch (error) {
    if (requestId === imageDefaultsRequestId) {
      console.error('Failed to load Docker image create defaults', error)
      getUiApi().message.warning(
        error instanceof Error ? error.message : '提取镜像端口和目录失败。',
      )
    }
  } finally {
    if (requestId === imageDefaultsRequestId) {
      loadingImageDefaults.value = false
    }
  }
}

async function submitCreateContainer() {
  if (!createForm.value.image?.trim()) {
    getUiApi().message.error('镜像名称不能为空。')
    return
  }

  creatingContainer.value = true
  try {
    const connectionId = requireConnectionId()
    const payload: DockerCreateContainerPayload = {
      image: createForm.value.image.trim(),
      name: createForm.value.name?.trim() || undefined,
      ports: toLineList(createPortsText.value),
      env: toLineList(createEnvText.value),
      volumes: toLineList(createVolumesText.value),
      restartPolicy: createForm.value.restartPolicy || 'no',
      cmd: toLineList(createCmdText.value),
      entrypoint: toLineList(createEntrypointText.value),
      start: createForm.value.start === true,
    }

    const result = await dockerApi.createContainer(connectionId, payload)
    window.dispatchEvent(new CustomEvent('docker:container-created', { detail: { connectionId } }))
    getUiApi().message.success(`容器创建成功：${result.containerId.slice(0, 12)}`)
    closeWindow()
  } catch (error) {
    console.error('Failed to create container', error)
    getUiApi().message.error(error instanceof Error ? error.message : '创建容器失败。')
  } finally {
    creatingContainer.value = false
  }
}

onMounted(() => {
  void loadImages()
})

watch(selectedImage, (image) => {
  void loadImageDefaults(image)
})
</script>

<template>
  <div
    class="flex h-full flex-col overflow-hidden"
    :class="
      settingsStore.isDark
        ? 'bg-[linear-gradient(180deg,rgba(15,23,42,0.18),rgba(15,23,42,0.06))]'
        : 'bg-[linear-gradient(180deg,rgba(255,255,255,0.7),rgba(226,232,240,0.36))]'
    "
  >
    <div
      class="flex shrink-0 flex-wrap items-center justify-between gap-[12px] border-b px-[18px] py-[14px]"
      :class="
        settingsStore.isDark
          ? 'border-[rgba(148,163,184,0.14)] text-[#e2e8f0]'
          : 'border-[rgba(148,163,184,0.22)] text-[#1e293b]'
      "
    >
      <div class="min-w-0">
        <div class="mb-[4px] flex items-center gap-[8px]">
          <NIcon :size="20"><LogoDocker /></NIcon>
          <h2 class="m-0 text-[18px]">新建容器</h2>
        </div>
      </div>

      <NButton round @click="loadImages" :loading="loadingImages">刷新镜像</NButton>
    </div>

    <NSpin :show="loadingImages" class="create-container-body min-h-0 flex-1 overflow-hidden">
      <div
        class="h-full min-h-0 overflow-auto p-[18px] app-scrollbar"
        :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'"
      >
        <NForm label-placement="top">
          <NGrid :cols="2" :x-gap="12" responsive="screen">
            <NFormItemGi label="镜像">
              <NSelect
                v-model:value="createForm.image"
                :options="createImageOptions"
                filterable
                tag
                placeholder="请选择或输入镜像"
              />
            </NFormItemGi>
            <NFormItemGi label="容器名称">
              <NInput v-model:value="createForm.name" placeholder="可选" />
            </NFormItemGi>
          </NGrid>

          <NGrid :cols="2" :x-gap="12" responsive="screen">
            <NFormItemGi label="重启策略">
              <NSelect
                v-model:value="createForm.restartPolicy"
                :options="[
                  { label: 'no', value: 'no' },
                  { label: 'always', value: 'always' },
                  { label: 'unless-stopped', value: 'unless-stopped' },
                  { label: 'on-failure', value: 'on-failure' },
                ]"
              />
            </NFormItemGi>
            <NFormItemGi label="创建后立即启动">
              <NSwitch v-model:value="createForm.start" />
            </NFormItemGi>
          </NGrid>

          <NFormItem label="端口映射">
            <NInput
              v-model:value="createPortsText"
              type="textarea"
              :rows="3"
              :loading="loadingImageDefaults"
              placeholder="每行一条，例如 8080:80"
            />
          </NFormItem>

          <NFormItem label="环境变量">
            <NInput
              v-model:value="createEnvText"
              type="textarea"
              :rows="3"
              placeholder="每行一条，例如 NODE_ENV=production"
            />
          </NFormItem>

          <NFormItem label="卷挂载">
            <NInput
              v-model:value="createVolumesText"
              type="textarea"
              :rows="3"
              :loading="loadingImageDefaults"
              placeholder="每行一条，例如 /opt/docker-volumes/app/data:/data；单独路径将创建匿名卷"
            />
          </NFormItem>

          <NFormItem label="启动命令 CMD">
            <NInput
              v-model:value="createCmdText"
              type="textarea"
              :rows="2"
              placeholder="每行一个参数"
            />
          </NFormItem>

          <NFormItem label="Entrypoint">
            <NInput
              v-model:value="createEntrypointText"
              type="textarea"
              :rows="2"
              placeholder="每行一个参数"
            />
          </NFormItem>
        </NForm>
      </div>
    </NSpin>

    <div
      class="flex shrink-0 justify-end border-t px-[18px] py-[12px] backdrop-blur-[14px] shadow-[0_-16px_36px_rgba(15,23,42,0.12)]"
      :class="
        settingsStore.isDark
          ? 'border-[rgba(148,163,184,0.14)] bg-[rgba(15,23,42,0.62)]'
          : 'border-[rgba(148,163,184,0.22)] bg-[rgba(248,250,252,0.68)]'
      "
    >
      <NSpace>
        <NButton @click="closeWindow">取消</NButton>
        <NButton type="primary" :loading="creatingContainer" @click="submitCreateContainer"
          >创建</NButton
        >
      </NSpace>
    </div>
  </div>
</template>

<style scoped>
.create-container-body :deep(.n-spin-container),
.create-container-body :deep(.n-spin-content) {
  height: 100%;
  min-height: 0;
}
</style>

<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import { dockerApi } from '@/api/docker'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

const props = defineProps<{
  windowId?: string
  connectionId?: string
}>()

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const outputElement = ref<HTMLElement>()
const imageName = ref('')
const output = ref('')
const error = ref('')
const pulling = ref(false)
let abortController: AbortController | null = null

const activeConnectionId = computed(() => props.connectionId ?? sshStore.connectionId)

function requireConnectionId() {
  const connectionId = activeConnectionId.value
  if (!connectionId) {
    throw new Error('当前没有可用的 Docker 连接。')
  }

  return connectionId
}

function appendOutput(text: string) {
  const maxLength = 1024 * 1024
  output.value = `${output.value}${text}`.slice(-maxLength)
}

function cancelPull() {
  abortController?.abort()
}

function closeWindow() {
  if (!pulling.value && props.windowId) {
    desktopStore.closeWindow(props.windowId)
  }
}

async function pullImage() {
  const image = imageName.value.trim()
  if (!image || pulling.value) {
    return
  }

  pulling.value = true
  output.value = `开始拉取镜像 ${image}\n\n`
  error.value = ''
  const controller = new AbortController()
  abortController = controller

  try {
    const result = await dockerApi.pullImageStream(
      requireConnectionId(),
      image,
      (event) => {
        if (event.event === 'progress') {
          const prefix = event.data.id ? `[${event.data.id}] ` : ''
          const status = event.data.status || '处理中'
          const progress = event.data.progress ? ` ${event.data.progress}` : ''
          appendOutput(`${prefix}${status}${progress}\n`)
        } else if (event.event === 'stderr') {
          appendOutput(event.data.text)
        } else if (event.event === 'error') {
          appendOutput(`\n[错误] ${event.data.message}\n`)
        }
      },
      controller.signal,
    )
    appendOutput(`\n> 镜像 ${result.image} 拉取完成\n`)
    window.dispatchEvent(
      new CustomEvent('docker:image-pulled', {
        detail: { connectionId: requireConnectionId() },
      }),
    )
    getUiApi().message.success(`镜像 ${image} 已拉取。`)
  } catch (caughtError) {
    if (controller.signal.aborted) {
      appendOutput('\n> 拉取已取消\n')
      return
    }

    console.error('Failed to pull image', caughtError)
    const message = caughtError instanceof Error ? caughtError.message : '拉取镜像失败。'
    error.value = message
    appendOutput(`\n[错误] ${message}\n`)
  } finally {
    pulling.value = false
    abortController = null
  }
}

watch(
  () => output.value.length,
  () => {
    void nextTick(() => {
      if (outputElement.value) {
        outputElement.value.scrollTop = outputElement.value.scrollHeight
      }
    })
  },
)

onBeforeUnmount(cancelPull)
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-[12px] p-[16px]">
    <NInput
      v-model:value="imageName"
      placeholder="镜像名称，如 nginx:latest"
      :disabled="pulling"
      @keyup.enter="pullImage"
    />
    <NAlert v-if="error" type="error" :show-icon="false">{{ error }}</NAlert>
    <pre
      ref="outputElement"
      class="app-radius-item docker-console mono-ui m-0 min-h-[180px] flex-1 overflow-auto whitespace-pre-wrap break-words rounded-[8px] p-[14px] text-[12px] leading-[1.6] app-scrollbar select-text"
      :class="
        settingsStore.isDark
          ? 'bg-[rgba(2,6,23,0.9)] text-[#dbeafe] app-scrollbar-dark'
          : 'bg-[rgba(248,250,252,0.96)] text-[rgba(30,41,59,0.96)] app-scrollbar-light'
      "
      >{{ output || '输入镜像名称后开始拉取。' }}</pre
    >
    <div class="flex shrink-0 justify-end gap-[8px]">
      <NButton v-if="pulling" @click="cancelPull">取消</NButton>
      <NButton v-else type="primary" :disabled="!imageName.trim()" @click="pullImage">
        开始拉取
      </NButton>
      <NButton :disabled="pulling" @click="closeWindow">关闭</NButton>
    </div>
  </div>
</template>

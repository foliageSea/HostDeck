<script setup lang="ts">
import { nextTick, ref, watch } from 'vue'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'

const props = defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()
const outputElement = ref<HTMLElement>()

watch(
  () => props.controller.pullImageOutput.length,
  () => {
    void nextTick(() => {
      if (outputElement.value) {
        outputElement.value.scrollTop = outputElement.value.scrollHeight
      }
    })
  },
)

function close() {
  if (props.controller.pullingImage) {
    props.controller.cancelPullImage()
    return
  }
  props.controller.pullImageVisible = false
}
</script>

<template>
  <NModal
    v-model:show="controller.pullImageVisible"
    preset="card"
    title="拉取镜像"
    :closable="!controller.pullingImage"
    :mask-closable="!controller.pullingImage"
    style="width: min(760px, 92vw)"
    @close="close"
  >
    <div class="flex flex-col gap-[12px]">
      <NInput
        v-model:value="controller.pullImageName"
        placeholder="镜像名称，如 nginx:latest"
        :disabled="controller.pullingImage"
        @keyup.enter="controller.pullImage"
      />
      <NAlert v-if="controller.pullImageError" type="error" :show-icon="false">
        {{ controller.pullImageError }}
      </NAlert>
      <pre
        ref="outputElement"
        class="app-radius-item docker-console mono-ui m-0 max-h-[50vh] min-h-[180px] overflow-auto whitespace-pre-wrap break-words rounded-[14px] p-[14px] text-[12px] leading-[1.6] app-scrollbar select-text"
        :class="
          settingsStore.isDark
            ? 'bg-[rgba(2,6,23,0.9)] text-[#dbeafe] app-scrollbar-dark'
            : 'bg-[rgba(248,250,252,0.96)] text-[rgba(30,41,59,0.96)] app-scrollbar-light'
        "
        >{{ controller.pullImageOutput || '输入镜像名称后开始拉取。' }}</pre
      >
      <div class="flex justify-end gap-[8px]">
        <NButton v-if="controller.pullingImage" @click="controller.cancelPullImage"> 取消 </NButton>
        <NButton
          v-else
          type="primary"
          :disabled="!controller.pullImageName.trim()"
          @click="controller.pullImage"
        >
          开始拉取
        </NButton>
        <NButton v-if="!controller.pullingImage" @click="controller.pullImageVisible = false">
          关闭
        </NButton>
      </div>
    </div>
  </NModal>
</template>

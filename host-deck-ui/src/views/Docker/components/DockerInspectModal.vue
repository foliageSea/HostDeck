<script setup lang="ts">
import { computed } from 'vue'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'

const props = defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()

const inspectText = computed(() =>
  props.controller.inspectContent ? JSON.stringify(props.controller.inspectContent, null, 2) : '',
)

async function copyInspect() {
  if (!inspectText.value) {
    return
  }

  try {
    await navigator.clipboard.writeText(inspectText.value)
    getUiApi().message.success('检查结果已复制到剪贴板。')
  } catch (error) {
    console.error('Failed to copy inspect content', error)
    getUiApi().message.error('复制检查结果失败。')
  }
}
</script>

<template>
  <NModal
    v-model:show="controller.inspectVisible"
    preset="card"
    :title="controller.inspectTitle"
    class="inspect-modal"
    style="width: min(960px, 92vw)"
  >
    <NSpin :show="controller.inspectLoading">
      <pre
        class="app-radius-item docker-console m-0 max-h-[65vh] select-text overflow-auto whitespace-pre-wrap break-words rounded-[14px] p-[14px] text-[12px] leading-[1.6] app-scrollbar"
        :class="
          settingsStore.isDark
            ? 'bg-[rgba(2,6,23,0.9)] text-[#dbeafe] app-scrollbar-dark'
            : 'bg-[rgba(248,250,252,0.96)] text-[rgba(30,41,59,0.96)] app-scrollbar-light'
        "
        >{{ inspectText }}</pre
      >
    </NSpin>

    <template #action>
      <NSpace justify="end">
        <NTooltip trigger="hover" placement="top">
          <template #trigger>
            <NButton :disabled="!inspectText" @click="copyInspect">复制全部</NButton>
          </template>
          复制完整检查结果，也可以直接在内容区选中文本复制。
        </NTooltip>
        <NButton type="primary" @click="controller.inspectVisible = false">关闭</NButton>
      </NSpace>
    </template>
  </NModal>
</template>

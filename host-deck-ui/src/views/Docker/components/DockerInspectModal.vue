<script setup lang="ts">
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()
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
        class="app-radius-item docker-console mono-ui m-0 max-h-[65vh] overflow-auto whitespace-pre-wrap break-words rounded-[14px] p-[14px] text-[12px] leading-[1.6] app-scrollbar"
        :class="
          settingsStore.isDark
            ? 'bg-[rgba(2,6,23,0.9)] text-[#dbeafe] app-scrollbar-dark'
            : 'bg-[rgba(248,250,252,0.96)] text-[rgba(30,41,59,0.96)] app-scrollbar-light'
        "
        >{{
          controller.inspectContent ? JSON.stringify(controller.inspectContent, null, 2) : ''
        }}</pre
      >
    </NSpin>
  </NModal>
</template>

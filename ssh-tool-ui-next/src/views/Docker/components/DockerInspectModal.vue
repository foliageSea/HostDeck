<script setup lang="ts">
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()
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
      <pre class="docker-console mono-ui m-0 max-h-[65vh] overflow-auto whitespace-pre-wrap break-words rounded-[14px] bg-[rgba(2,6,23,0.9)] p-[14px] text-[12px] leading-[1.6] text-[#dbeafe] app-scrollbar app-scrollbar-dark">{{ controller.inspectContent ? JSON.stringify(controller.inspectContent, null, 2) : '' }}</pre>
    </NSpin>
  </NModal>
</template>

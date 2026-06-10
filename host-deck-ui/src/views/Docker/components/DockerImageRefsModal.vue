<script setup lang="ts">
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()
</script>

<template>
  <NModal
    v-model:show="controller.imageRefsVisible"
    preset="card"
    :title="controller.imageRefsTitle"
    style="width: min(960px, 92vw)"
  >
    <NSpin :show="controller.imageRefsLoading">
      <NDataTable
        :single-line="false"
        :columns="controller.imageRefsColumns"
        :data="controller.imageRefsItems"
        size="small"
      />
    </NSpin>
  </NModal>
</template>

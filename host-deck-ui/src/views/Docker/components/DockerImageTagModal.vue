<script setup lang="ts">
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()
</script>

<template>
  <NModal v-model:show="controller.imageTagVisible" preset="card" title="镜像重新打标签" style="width: min(560px, 92vw)">
    <NForm label-placement="top">
      <NFormItem label="源镜像">
        <NInput v-model:value="controller.imageTagSource" readonly />
      </NFormItem>
      <NFormItem label="目标标签">
        <NInput v-model:value="controller.imageTagTarget" placeholder="例如 my-nginx:stable" />
      </NFormItem>
    </NForm>

    <template #footer>
      <NSpace justify="end">
        <NButton @click="controller.imageTagVisible = false">取消</NButton>
        <NButton type="primary" :loading="controller.imageTagging" @click="controller.submitTagImage">确认</NButton>
      </NSpace>
    </template>
  </NModal>
</template>

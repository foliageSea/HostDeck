<script setup lang="ts">
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()
</script>

<template>
  <NModal v-model:show="controller.renameVisible" preset="card" title="重命名容器" style="width: min(520px, 92vw)">
    <NForm label-placement="top">
      <NFormItem label="新名称">
        <NInput v-model:value="controller.renamingContainerName" placeholder="输入新的容器名称" />
      </NFormItem>
    </NForm>

    <template #footer>
      <NSpace justify="end">
        <NButton @click="controller.renameVisible = false">取消</NButton>
        <NButton type="primary" :loading="controller.renamingContainer" @click="controller.submitRenameContainer">保存</NButton>
      </NSpace>
    </template>
  </NModal>
</template>

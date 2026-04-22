<script setup lang="ts">
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()
</script>

<template>
  <NModal
    v-model:show="controller.createVisible"
    preset="card"
    title="新建容器"
    style="width: min(760px, 94vw)"
  >
    <NForm label-placement="top">
      <NGrid :cols="2" :x-gap="12">
        <NFormItemGi label="镜像">
          <NSelect
            v-model:value="controller.createForm.image"
            :options="controller.createImageOptions"
            filterable
            tag
            placeholder="请选择或输入镜像"
          />
        </NFormItemGi>
        <NFormItemGi label="容器名称">
          <NInput v-model:value="controller.createForm.name" placeholder="可选" />
        </NFormItemGi>
      </NGrid>

      <NGrid :cols="2" :x-gap="12">
        <NFormItemGi label="重启策略">
          <NSelect
            v-model:value="controller.createForm.restartPolicy"
            :options="[
              { label: 'no', value: 'no' },
              { label: 'always', value: 'always' },
              { label: 'unless-stopped', value: 'unless-stopped' },
              { label: 'on-failure', value: 'on-failure' },
            ]"
          />
        </NFormItemGi>
        <NFormItemGi label="创建后立即启动">
          <NSwitch v-model:value="controller.createForm.start" />
        </NFormItemGi>
      </NGrid>

      <NFormItem label="端口映射">
        <NInput v-model:value="controller.createPortsText" type="textarea" :rows="3" placeholder="每行一条，例如 8080:80" />
      </NFormItem>

      <NFormItem label="环境变量">
        <NInput v-model:value="controller.createEnvText" type="textarea" :rows="3" placeholder="每行一条，例如 NODE_ENV=production" />
      </NFormItem>

      <NFormItem label="卷挂载">
        <NInput v-model:value="controller.createVolumesText" type="textarea" :rows="3" placeholder="每行一条，例如 /host/data:/data" />
      </NFormItem>

      <NFormItem label="启动命令 CMD">
        <NInput v-model:value="controller.createCmdText" type="textarea" :rows="2" placeholder="每行一个参数" />
      </NFormItem>

      <NFormItem label="Entrypoint">
        <NInput v-model:value="controller.createEntrypointText" type="textarea" :rows="2" placeholder="每行一个参数" />
      </NFormItem>
    </NForm>

    <template #footer>
      <NSpace justify="end">
        <NButton @click="controller.createVisible = false">取消</NButton>
        <NButton type="primary" :loading="controller.creatingContainer" @click="controller.submitCreateContainer">创建</NButton>
      </NSpace>
    </template>
  </NModal>
</template>

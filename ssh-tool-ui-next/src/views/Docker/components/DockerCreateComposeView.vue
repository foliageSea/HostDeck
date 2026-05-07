<script setup lang="ts">
import { ref } from 'vue'
import { LogoDocker } from '@vicons/ionicons5'
import CodeEditor from '@/components/editor/CodeEditor.vue'
import { dockerApi, type DockerComposeCreatePayload } from '@/api/docker'
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
const creatingComposeProject = ref(false)
const createForm = ref<DockerComposeCreatePayload>({
  projectName: '',
  workingDir: '',
  fileName: 'docker-compose.yml',
  content: `services:
  app:
    image: nginx:latest
    ports:
      - "18080:80"
    restart: unless-stopped
`,
  startAfterCreate: true,
})

function requireConnectionId() {
  const connectionId = props.connectionId ?? sshStore.connectionId
  if (!connectionId) {
    throw new Error('当前没有可用的 Docker 连接。')
  }

  return connectionId
}

function closeWindow() {
  if (props.windowId) {
    desktopStore.closeWindow(props.windowId)
  }
}

async function submitCreateComposeProject() {
  const payload: DockerComposeCreatePayload = {
    projectName: createForm.value.projectName.trim(),
    workingDir: createForm.value.workingDir.trim(),
    fileName: createForm.value.fileName.trim() || 'docker-compose.yml',
    content: createForm.value.content,
    startAfterCreate: createForm.value.startAfterCreate === true,
  }

  if (!payload.projectName || !payload.workingDir || !payload.content.trim()) {
    getUiApi().message.error('项目名、工作目录和 Compose 内容不能为空。')
    return
  }

  creatingComposeProject.value = true
  try {
    const connectionId = requireConnectionId()
    const result = await dockerApi.createComposeProject(connectionId, payload)
    window.dispatchEvent(new CustomEvent('docker:compose-created', {
      detail: {
        connectionId,
        project: {
          configFiles: result.configFiles.join(', '),
          name: result.projectName,
          status: result.started ? 'running' : 'created',
          workingDir: result.workingDir,
        },
      },
    }))
    if (result.startError) {
      getUiApi().message.warning(`编排项目已创建，但启动失败：${result.startError}`)
    } else {
      getUiApi().message.success(payload.startAfterCreate ? '编排项目已创建并启动。' : '编排项目已创建。')
    }
    closeWindow()
  } catch (error) {
    console.error('Failed to create compose project', error)
    getUiApi().message.error(error instanceof Error ? error.message : '创建编排项目失败。')
  } finally {
    creatingComposeProject.value = false
  }
}
</script>

<template>
  <div class="flex h-full flex-col overflow-hidden"
    :class="settingsStore.isDark ? 'bg-[linear-gradient(180deg,rgba(15,23,42,0.18),rgba(15,23,42,0.06))]' : 'bg-[linear-gradient(180deg,rgba(255,255,255,0.7),rgba(226,232,240,0.36))]'">
    <div class="flex shrink-0 flex-wrap items-center justify-between gap-[12px] border-b px-[18px] py-[14px]"
      :class="settingsStore.isDark ? 'border-[rgba(148,163,184,0.14)] text-[#e2e8f0]' : 'border-[rgba(148,163,184,0.22)] text-[#1e293b]'">
      <div class="min-w-0">
        <div class="mb-[4px] flex items-center gap-[8px]">
          <NIcon :size="20">
            <LogoDocker />
          </NIcon>
          <h2 class="m-0 text-[18px]">新建编排</h2>
        </div>
      </div>

      <NSpace>
        <NButton round quaternary @click="closeWindow">关闭</NButton>
      </NSpace>
    </div>

    <div class="create-compose-body min-h-0 min-w-0 flex-1 overflow-hidden p-[18px]">
      <NForm label-placement="top" class="create-compose-form h-full min-h-0 min-w-0 overflow-auto app-scrollbar"
        :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'">
        <NGrid :cols="2" :x-gap="12" responsive="screen">
          <NFormItemGi label="项目名" required>
            <NInput v-model:value="createForm.projectName" placeholder="例如 my-stack" />
          </NFormItemGi>
          <NFormItemGi label="文件名" required>
            <NInput v-model:value="createForm.fileName" placeholder="docker-compose.yml" />
          </NFormItemGi>
        </NGrid>

        <NFormItem label="远端工作目录" required class="mt-2">
          <NInput v-model:value="createForm.workingDir" placeholder="例如 /opt/my-stack" />
        </NFormItem>

        <NFormItem label="Compose YAML" required class="mt-2">
          <div class="compose-editor-wrap h-[420px] min-h-[320px] min-w-0 w-full">
            <CodeEditor v-model="createForm.content" language="yaml" class="h-full min-h-0" />
          </div>
        </NFormItem>

        <NFormItem label="创建后立即启动">
          <NSwitch v-model:value="createForm.startAfterCreate" />
        </NFormItem>
      </NForm>
    </div>

    <div
      class="flex shrink-0 justify-end border-t px-[18px] py-[12px] backdrop-blur-[14px] shadow-[0_-16px_36px_rgba(15,23,42,0.12)]"
      :class="settingsStore.isDark ? 'border-[rgba(148,163,184,0.14)] bg-[rgba(15,23,42,0.62)]' : 'border-[rgba(148,163,184,0.22)] bg-[rgba(248,250,252,0.68)]'">
      <NSpace>
        <NButton @click="closeWindow">取消</NButton>
        <NButton type="primary" :loading="creatingComposeProject" @click="submitCreateComposeProject">创建</NButton>
      </NSpace>
    </div>
  </div>
</template>

<style scoped>
.create-compose-body,
.create-compose-form,
.compose-editor-wrap {
  min-height: 0;
}

.create-compose-body,
.create-compose-form,
.compose-editor-wrap {
  min-width: 0;
}

.create-compose-form {
  height: 100%;
  width: 100%;
}

.create-compose-body :deep(.n-form),
.create-compose-body :deep(.n-form-item),
.create-compose-body :deep(.n-form-item-blank),
.create-compose-body :deep(.n-form-item-feedback-wrapper) {
  min-height: 0;
  min-width: 0;
  width: 100%;
}

.compose-editor-wrap {
  display: flex;
  overflow: hidden;
}

.compose-editor-wrap>* {
  flex: 1;
  min-height: 0;
}
</style>

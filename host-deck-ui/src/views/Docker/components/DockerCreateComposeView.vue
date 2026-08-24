<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { LogoDocker } from '@vicons/ionicons5'
import CodeEditor from '@/components/editor/CodeEditor.vue'
import {
  dockerApi,
  type DockerComposeCreatePayload,
  type DockerComposeProject,
} from '@/api/docker'
import { filesApi } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useDockerOutputStore } from '@/stores/docker-output'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import { FilePickerDialog, type FilePickerConfirmPayload } from '@/views/Files/components'
import { resolve } from '@/utils/path'
import { getComposeConfigFiles } from '../hooks/dockerViewHelpers'

const props = defineProps<{
  windowId?: string
  connectionId?: string
  host?: string
  project?: DockerComposeProject
}>()
const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const outputStore = useDockerOutputStore()
const creating = ref(false)
const pickerVisible = ref(false)
const form = ref<DockerComposeCreatePayload>({
  projectName: '',
  workingDir: '',
  fileName: 'docker-compose.yml',
  content:
    'services:\n  app:\n    image: nginx:latest\n    ports:\n      - "18080:80"\n    restart: unless-stopped\n',
  startAfterCreate: true,
})
const connectionId = computed(() => props.connectionId ?? sshStore.connectionId)
const editing = computed(() => Boolean(props.project))
function close() {
  if (props.windowId) desktopStore.closeWindow(props.windowId)
}
const composeFileNames = [
  'compose.yaml',
  'compose.yml',
  'docker-compose.yaml',
  'docker-compose.yml',
]

async function loadExistingComposeFile(connectionId: string, directory: string, fileName: string) {
  try {
    form.value.fileName = fileName
    form.value.content = await filesApi.readFile(connectionId, resolve(directory, fileName))
    getUiApi().message.success(`已加载配置文件 ${fileName}。`)
  } catch (error) {
    console.error('Failed to read existing compose file', error)
    getUiApi().message.error('配置文件读取失败，已保留当前内容。')
  }
}

async function loadProjectForEditing() {
  const project = props.project
  const selectedConnectionId = connectionId.value
  const configFile = project ? getComposeConfigFiles(project)[0] : undefined
  if (!project || !selectedConnectionId || !configFile) return

  const separatorIndex = Math.max(configFile.lastIndexOf('/'), configFile.lastIndexOf('\\'))
  form.value.projectName = project.name
  form.value.workingDir = project.workingDir || configFile.slice(0, separatorIndex) || '/'
  form.value.fileName = configFile.slice(separatorIndex + 1)
  form.value.startAfterCreate = false
  await loadExistingComposeFile(selectedConnectionId, form.value.workingDir, form.value.fileName)
}

async function picked(value: FilePickerConfirmPayload) {
  const selectedPath = value.selections[0]?.path
  const selectedConnectionId = connectionId.value
  if (!selectedPath || !selectedConnectionId) return

  form.value.workingDir = selectedPath
  try {
    const files = await filesApi.list(selectedConnectionId, selectedPath)
    const names = new Set(files.filter((file) => !file.isDirectory).map((file) => file.filename))
    const existingFileName = [form.value.fileName.trim(), ...composeFileNames].find((name) =>
      names.has(name),
    )
    if (!existingFileName) return

    const dialog = getUiApi().dialog.warning({
      title: '发现已有 Compose 配置',
      content: `目录 ${selectedPath} 中已存在 ${existingFileName}，是否加载该配置文件？`,
      positiveText: '加载配置',
      negativeText: '继续新建',
      onPositiveClick: async () => {
        dialog.loading = true
        try {
          await loadExistingComposeFile(selectedConnectionId, selectedPath, existingFileName)
        } finally {
          dialog.loading = false
        }
      },
    })
  } catch (error) {
    console.error('Failed to inspect compose directory', error)
    getUiApi().message.error('配置文件检查失败，请检查目录访问权限。')
  }
}
async function submit() {
  const payload = {
    ...form.value,
    projectName: form.value.projectName.trim(),
    workingDir: form.value.workingDir.trim(),
    fileName: form.value.fileName.trim() || 'docker-compose.yml',
  }
  if (!connectionId.value || !payload.projectName || !payload.workingDir || !payload.content.trim())
    return getUiApi().message.error('项目名、工作目录和 Compose 内容不能为空。')
  creating.value = true
  try {
    const title = `${editing.value ? '编辑' : '创建'}编排 · ${payload.projectName}`
    const taskId = outputStore.createTask(connectionId.value, title)
    desktopStore.openWindow(
      'docker-output',
      { taskId, title },
      { maximizable: false, parentId: props.windowId, resizable: false },
    )
    const result = await outputStore.runTask(taskId, ({ append, signal }) =>
      dockerApi.createComposeProjectStream(
        connectionId.value!,
        payload,
        (event) => {
          if (event.event === 'phase') append(`> ${event.data.message}\n`)
          else if (event.event === 'stdout' || event.event === 'stderr') append(event.data.text)
          else if (event.event === 'error') append(`\n[错误] ${event.data.message}\n`)
        },
        signal,
      ),
    )
    window.dispatchEvent(
      new CustomEvent('docker:compose-created', {
        detail: {
          connectionId: connectionId.value,
          project: {
            configFiles: result.configFiles.join(', '),
            name: result.projectName,
            status: result.started ? 'running' : 'created',
            workingDir: result.workingDir,
          },
        },
      }),
    )
    if (result.started) {
      getUiApi().message.success(`编排项目已${editing.value ? '保存并启动' : '创建并启动'}。`)
    } else if (payload.startAfterCreate) {
      getUiApi().message.warning(`编排项目已${editing.value ? '保存' : '创建'}，但启动失败。`)
    } else {
      getUiApi().message.success(`编排项目已${editing.value ? '保存' : '创建'}。`)
    }
    close()
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '创建编排项目失败。')
  } finally {
    creating.value = false
  }
}
onMounted(() => void loadProjectForEditing())
</script>
<template>
  <div
    class="flex h-full flex-col overflow-hidden"
    :class="
      settingsStore.isDark
        ? 'bg-[linear-gradient(180deg,rgba(15,23,42,.18),rgba(15,23,42,.06))]'
        : 'bg-[linear-gradient(180deg,rgba(255,255,255,.7),rgba(226,232,240,.36))]'
    "
  >
    <div class="flex shrink-0 items-center gap-[8px] border-b px-[18px] py-[14px]">
      <NIcon :size="20"><LogoDocker /></NIcon>
      <h2 class="m-0 text-[18px]">{{ editing ? '编辑编排' : '新建编排' }}</h2>
    </div>
    <NForm label-placement="top" class="min-h-0 flex-1 overflow-auto p-[18px] app-scrollbar"
      ><NGrid :cols="2" :x-gap="12" responsive="screen"
        ><NFormItemGi label="项目名" required
          ><NInput v-model:value="form.projectName" placeholder="my-stack" /></NFormItemGi
        ><NFormItemGi label="文件名" required
          ><NInput v-model:value="form.fileName" /></NFormItemGi></NGrid
      ><NFormItem label="配置文件目录" required
        ><div class="flex w-full gap-[8px]">
          <NInput v-model:value="form.workingDir" placeholder="/opt/my-stack" /><NButton
            :disabled="!connectionId"
            @click="pickerVisible = true"
            >选择目录</NButton
          >
        </div></NFormItem
      ><NFormItem label="创建后立即启动"
        ><NSwitch v-model:value="form.startAfterCreate" /></NFormItem
      ><NFormItem label="Compose YAML" required
        ><div class="h-[420px] min-h-[320px] w-full overflow-hidden">
          <CodeEditor v-model="form.content" language="yaml" class="compose-editor h-full" /></div></NFormItem
    ></NForm>
    <div class="flex shrink-0 justify-end border-t px-[18px] py-[12px]">
      <NSpace
        ><NButton @click="close">取消</NButton
        ><NButton type="primary" :loading="creating" @click="submit">{{ editing ? '保存' : '创建' }}</NButton></NSpace
      >
    </div>
    <FilePickerDialog
      v-model:show="pickerVisible"
      :connection-id="connectionId"
      :initial-path="form.workingDir || '/'"
      mode="directory"
      title="选择配置文件目录"
      confirm-text="使用此目录"
      @confirm="picked"
    />
  </div>
</template>

<style scoped>
.compose-editor {
  border-radius: 0;
}
</style>

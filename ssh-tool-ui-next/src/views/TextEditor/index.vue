<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import CodeEditor from '@/components/editor/CodeEditor.vue'
import { filesApi } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'

const props = defineProps<{
  connectionId: string
  path: string
  windowId?: string
}>()

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const content = ref('')
const savedContent = ref('')
const showSettings = ref(false)
const editorFontFamilyDraft = ref(settingsStore.editorFontFamily)
const confirmingUnsavedChanges = ref(false)

const language = computed(() => detectLanguage(props.path))
const hasUnsavedChanges = computed(() => content.value !== savedContent.value)

const menuOptions = computed(() => [
  {
    key: 'file',
    label: '文件',
    children: [
      { key: 'save', label: hasUnsavedChanges.value ? '保存 *' : '保存', disabled: saving.value },
      { key: 'reload', label: '重新加载', disabled: loading.value || saving.value },
      { key: 'divider', type: 'divider' },
      { key: 'close', label: '关闭' },
    ],
  },
  {
    key: 'view',
    label: '查看',
    children: [
      { key: 'settings', label: '设置' },
    ],
  },
])

const languageByFilename: Record<string, string> = {
  '.bash_profile': 'shell',
  '.bashrc': 'shell',
  '.editorconfig': 'ini',
  '.gitconfig': 'ini',
  '.profile': 'shell',
  '.zshrc': 'shell',
  config: 'ini',
  dockerfile: 'dockerfile',
}

const languageByExtension: Record<string, string> = {
  bash: 'shell',
  bat: 'bat',
  c: 'c',
  cc: 'cpp',
  cjs: 'javascript',
  conf: 'ini',
  cpp: 'cpp',
  cs: 'csharp',
  cts: 'typescript',
  cxx: 'cpp',
  dart: 'dart',
  gql: 'graphql',
  graphql: 'graphql',
  h: 'c',
  hh: 'cpp',
  hpp: 'cpp',
  htm: 'html',
  htmx: 'html',
  hxx: 'cpp',
  ini: 'ini',
  java: 'java',
  js: 'javascript',
  json: 'json',
  jsx: 'javascript',
  kt: 'kotlin',
  kts: 'kotlin',
  less: 'less',
  lua: 'lua',
  md: 'markdown',
  mjs: 'javascript',
  mts: 'typescript',
  phtml: 'php',
  php: 'php',
  pl: 'perl',
  pm: 'perl',
  properties: 'ini',
  proto: 'protobuf',
  ps1: 'powershell',
  psd1: 'powershell',
  psm1: 'powershell',
  py: 'python',
  r: 'r',
  rb: 'ruby',
  rs: 'rust',
  scala: 'scala',
  scss: 'scss',
  sh: 'shell',
  sql: 'sql',
  swift: 'swift',
  ts: 'typescript',
  tsx: 'typescript',
  txt: 'plaintext',
  vue: 'html',
  xml: 'xml',
  yaml: 'yaml',
  yml: 'yaml',
  zsh: 'shell',
}

function detectLanguage(path: string) {
  const lowerPath = path.toLowerCase()
  const name = lowerPath.split('/').pop() || lowerPath

  if (lowerPath.endsWith('.d.ts') || lowerPath.endsWith('.ts') || lowerPath.endsWith('.mts') || lowerPath.endsWith('.cts')) {
    return 'typescript'
  }

  const filenameLanguage = languageByFilename[name]
  if (filenameLanguage) {
    return filenameLanguage
  }

  const extensionIndex = name.lastIndexOf('.')
  if (extensionIndex >= 0 && extensionIndex < name.length - 1) {
    const extension = name.slice(extensionIndex + 1)
    const extensionLanguage = languageByExtension[extension]
    if (extensionLanguage) {
      return extensionLanguage
    }
  }

  return 'plaintext'
}

function applyEditorSettings() {
  const nextFontFamily = editorFontFamilyDraft.value.trim()

  if (nextFontFamily) {
    settingsStore.setEditorFontFamily(nextFontFamily)
  } else {
    editorFontFamilyDraft.value = settingsStore.editorFontFamily
  }

  showSettings.value = false
}

function resetEditorSettings() {
  settingsStore.resetEditorSettings()
  editorFontFamilyDraft.value = settingsStore.editorFontFamily
}

function confirmDiscardUnsavedChanges(contentText: string) {
  if (!hasUnsavedChanges.value) {
    return Promise.resolve(true)
  }

  if (confirmingUnsavedChanges.value) {
    return Promise.resolve(false)
  }

  confirmingUnsavedChanges.value = true

  return new Promise<boolean>((resolve) => {
    let settled = false
    const settle = (value: boolean) => {
      if (settled) {
        return
      }

      settled = true
      confirmingUnsavedChanges.value = false
      resolve(value)
    }

    getUiApi().dialog.warning({
      title: '存在未保存的修改',
      content: contentText,
      positiveText: '放弃修改',
      negativeText: '取消',
      onPositiveClick: () => settle(true),
      onNegativeClick: () => settle(false),
      onClose: () => settle(false),
      onMaskClick: () => settle(false),
    })
  })
}

async function confirmCloseWindow() {
  return confirmDiscardUnsavedChanges('关闭窗口将丢失当前未保存的修改，是否继续？')
}

async function loadFile() {
  loading.value = true
  error.value = ''

  try {
    const nextContent = await filesApi.readFile(props.connectionId, props.path)
    content.value = nextContent
    savedContent.value = nextContent
  } catch (loadError) {
    console.error('Failed to read file', loadError)
    error.value = '文件读取失败。'
  } finally {
    loading.value = false
  }
}

async function saveFile() {
  if (saving.value) {
    return
  }

  saving.value = true
  try {
    await filesApi.writeFile(props.connectionId, props.path, content.value)
    savedContent.value = content.value
    getUiApi().message.success('文件已保存。')
  } catch (saveError) {
    console.error('Failed to save file', saveError)
    getUiApi().message.error('保存失败。')
  } finally {
    saving.value = false
  }
}

function closeWindow() {
  if (props.windowId) {
    void desktopStore.requestCloseWindow(props.windowId)
  }
}

async function reloadFile() {
  if (!await confirmDiscardUnsavedChanges('重新加载将丢失当前未保存的修改，是否继续？')) {
    return
  }

  await loadFile()
}

function handleActionSelect(key: string) {
  switch (key) {
    case 'save':
      void saveFile()
      break
    case 'reload':
      void reloadFile()
      break
    case 'settings':
      showSettings.value = true
      break
    case 'close':
      closeWindow()
      break
  }
}

function handleKeydown(event: KeyboardEvent) {
  if (event.ctrlKey && event.key.toLowerCase() === 's') {
    event.preventDefault()
    void saveFile()
  }
}

void loadFile()

onMounted(() => {
  if (props.windowId) {
    desktopStore.setWindowBeforeClose(props.windowId, confirmCloseWindow)
  }

  window.addEventListener('keydown', handleKeydown)
})

onBeforeUnmount(() => {
  if (props.windowId) {
    desktopStore.setWindowBeforeClose(props.windowId)
  }

  window.removeEventListener('keydown', handleKeydown)
})

watch(
  () => settingsStore.editorFontFamily,
  (value) => {
    editorFontFamilyDraft.value = value
  },
)

watch(showSettings, (value) => {
  if (value) {
    editorFontFamilyDraft.value = settingsStore.editorFontFamily
  }
})

</script>

<template>
  <div
    class="text-editor-view relative flex h-full flex-col gap-[12px] overflow-hidden p-[12px]"
    :class="settingsStore.isDark ? 'bg-[linear-gradient(180deg,rgba(15,23,42,0.18),rgba(15,23,42,0.06))]' : 'bg-[linear-gradient(180deg,rgba(255,255,255,0.7),rgba(226,232,240,0.36))]'"
  >
    <div
      class="relative z-[1] flex h-[32px] shrink-0 items-center gap-[4px] overflow-visible px-[8px]"
      :class="settingsStore.isDark ? 'text-[#e2e8f0]' : 'text-[#1e293b]'"
    >
      <NMenu class="notepad-menu" mode="horizontal" :options="menuOptions" responsive @update:value="handleActionSelect" />
      <span
        v-if="hasUnsavedChanges"
        class="ml-[8px] shrink-0 whitespace-nowrap rounded-full px-[10px] py-[3px] text-[12px] font-600"
        :class="settingsStore.isDark ? 'bg-[rgba(251,191,36,0.16)] text-[#fbbf24]' : 'bg-[rgba(245,158,11,0.14)] text-[#b45309]'"
      >
        未保存
      </span>
    </div>

    <NSpin :show="loading" class="editor-body relative z-[1] flex-1 min-h-0">
      <NResult v-if="error" status="error" title="无法读取文件" :description="error">
        <template #footer>
          <NButton round @click="reloadFile">重试</NButton>
        </template>
      </NResult>

      <CodeEditor v-else v-model="content" :language="language" class="h-full min-h-0" />
    </NSpin>

    <NModal
      :show="showSettings"
      preset="card"
      title="编辑器设置"
      style="width: min(380px, calc(100vw - 24px))"
      @update:show="(value: boolean) => showSettings = value"
    >
      <NSpace vertical size="large">
        <div>
          <div class="mb-[10px] text-[13px] text-[rgba(148,163,184,0.92)]">字体大小</div>
          <NSlider
            :value="settingsStore.editorFontSize"
            :min="8"
            :max="32"
            :tooltip="false"
            @update:value="(value: number) => settingsStore.setEditorFontSize(value)"
          />
        </div>

        <div>
          <div class="mb-[10px] text-[13px] text-[rgba(148,163,184,0.92)]">字体名称</div>
          <NInput
            :value="editorFontFamilyDraft"
            placeholder="例如 Consolas, monospace"
            @update:value="(value: string) => editorFontFamilyDraft = value"
            @blur="() => {
              const nextValue = editorFontFamilyDraft.trim()
              if (nextValue) {
                settingsStore.setEditorFontFamily(nextValue)
              }
            }"
          />
        </div>

        <NSpace justify="end">
          <NButton round @click="resetEditorSettings">恢复默认</NButton>
          <NButton round type="primary" @click="applyEditorSettings">完成</NButton>
        </NSpace>
      </NSpace>
    </NModal>
  </div>
</template>

<style scoped>
.text-editor-view::before {
  content: '';
  position: absolute;
  inset: 0;
  pointer-events: none;
  background:
    radial-gradient(circle at 14% 16%, rgba(59, 130, 246, 0.14), transparent 26%),
    radial-gradient(circle at 86% 12%, rgba(168, 85, 247, 0.1), transparent 20%);
}

.notepad-menu {
  height: 32px;
  line-height: 32px;
}

.notepad-menu :deep(.n-menu-item-content) {
  height: 32px;
  line-height: 32px;
  padding-top: 0;
  padding-bottom: 0;
}

.notepad-menu :deep(.n-menu-item-content-header) {
  line-height: 32px;
}

.editor-body :deep(.n-spin-body),
.editor-body :deep(.n-spin-content) {
  height: 100%;
  min-height: 0;
}

.editor-body :deep(.n-spin-content) {
  display: flex;
  flex-direction: column;
}

.editor-body :deep(.n-result) {
  margin: auto;
}

</style>

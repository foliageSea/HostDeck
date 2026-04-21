<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import * as monaco from 'monaco-editor'
import { filesApi } from '@/api/files'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'

const props = defineProps<{
  path: string
  sessionId: string
  windowId?: string
}>()

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const content = ref('')
const editorContainer = ref<HTMLElement | null>(null)
const showSettings = ref(false)
const editorFontFamilyDraft = ref(settingsStore.editorFontFamily)

let editor: monaco.editor.IStandaloneCodeEditor | null = null
let model: monaco.editor.ITextModel | null = null
let syncDisposable: monaco.IDisposable | null = null

const filename = computed(() => props.path.split('/').pop() || props.path)

const language = computed(() => detectLanguage(props.path))

function detectLanguage(path: string) {
  const lowerPath = path.toLowerCase()

  if (lowerPath.endsWith('.d.ts') || lowerPath.endsWith('.ts') || lowerPath.endsWith('.mts') || lowerPath.endsWith('.cts')) {
    return 'typescript'
  }

  if (lowerPath.endsWith('.js') || lowerPath.endsWith('.mjs') || lowerPath.endsWith('.cjs')) {
    return 'javascript'
  }

  if (lowerPath.endsWith('.json')) {
    return 'json'
  }

  if (lowerPath.endsWith('.md')) {
    return 'markdown'
  }

  if (lowerPath.endsWith('.py')) {
    return 'python'
  }

  if (lowerPath.endsWith('.sh') || lowerPath.endsWith('.bash') || lowerPath.endsWith('.zsh')) {
    return 'shell'
  }

  if (lowerPath.endsWith('.yml') || lowerPath.endsWith('.yaml')) {
    return 'yaml'
  }

  if (lowerPath.endsWith('.xml')) {
    return 'xml'
  }

  if (lowerPath.endsWith('.html') || lowerPath.endsWith('.htm') || lowerPath.endsWith('.vue')) {
    return 'html'
  }

  if (lowerPath.endsWith('.css')) {
    return 'css'
  }

  if (lowerPath.endsWith('.scss')) {
    return 'scss'
  }

  if (lowerPath.endsWith('.less')) {
    return 'less'
  }

  if (lowerPath.endsWith('.sql')) {
    return 'sql'
  }

  if (lowerPath.endsWith('.java')) {
    return 'java'
  }

  if (lowerPath.endsWith('.go')) {
    return 'go'
  }

  if (lowerPath.endsWith('.rs')) {
    return 'rust'
  }

  if (lowerPath.endsWith('.php')) {
    return 'php'
  }

  return 'plaintext'
}

function syncEditorContent(nextContent: string) {
  if (!model || model.getValue() === nextContent) {
    return
  }

  model.setValue(nextContent)
}

function updateEditorFontOptions(options: { fontFamily?: string, fontSize?: number }) {
  if (!editor) {
    return
  }

  editor.updateOptions(options)

  if (options.fontFamily !== undefined) {
    monaco.editor.remeasureFonts()
  }

  editor.layout()
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

async function initEditor() {
  await nextTick()

  if (!editorContainer.value || editor) {
    return
  }

  model = monaco.editor.createModel(content.value, language.value)
  editor = monaco.editor.create(editorContainer.value, {
    model,
    automaticLayout: true,
    minimap: { enabled: false },
    fontSize: settingsStore.editorFontSize,
    fontFamily: settingsStore.editorFontFamily,
    scrollBeyondLastLine: false,
    wordWrap: 'off',
    tabSize: 2,
    theme: 'vs-dark',
  })

  syncDisposable = editor.onDidChangeModelContent(() => {
    content.value = editor?.getValue() ?? ''
  })
}

function disposeEditor() {
  syncDisposable?.dispose()
  syncDisposable = null
  editor?.dispose()
  editor = null
  model?.dispose()
  model = null
}

async function loadFile() {
  loading.value = true
  error.value = ''

  try {
    content.value = await filesApi.readFile(props.sessionId, props.path)
    syncEditorContent(content.value)

    if (model) {
      monaco.editor.setModelLanguage(model, language.value)
    }
  } catch (loadError) {
    console.error('Failed to read file', loadError)
    error.value = '文件读取失败。'
  } finally {
    loading.value = false
  }
}

async function saveFile() {
  saving.value = true
  try {
    await filesApi.writeFile(props.sessionId, props.path, content.value)
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
    desktopStore.closeWindow(props.windowId)
  }
}

onMounted(() => {
  void initEditor()
  void loadFile()
})

onBeforeUnmount(() => {
  disposeEditor()
})

watch(
  () => settingsStore.editorFontSize,
  (value) => {
    updateEditorFontOptions({ fontSize: value })
  },
)

watch(
  () => settingsStore.editorFontFamily,
  (value) => {
    editorFontFamilyDraft.value = value
    updateEditorFontOptions({ fontFamily: value })
  },
)

watch(showSettings, (value) => {
  if (value) {
    editorFontFamilyDraft.value = settingsStore.editorFontFamily
  }
})
</script>

<template>
  <div class="flex h-full flex-col bg-[rgba(15,23,42,0.2)]">
    <div class="flex items-center justify-between gap-[12px] border-b border-[rgba(148,163,184,0.14)] px-[14px] py-[12px]">
      <div class="flex min-w-0 flex-col gap-[4px]">
        <strong>{{ filename }}</strong>
        <span class="truncate-line text-[12px] text-[rgba(148,163,184,0.9)]">{{ props.path }}</span>
      </div>

      <NSpace>
        <NButton @click="showSettings = true">设置</NButton>
        <NButton @click="loadFile">重新加载</NButton>
        <NButton type="primary" :loading="saving" @click="saveFile">保存</NButton>
        <NButton quaternary @click="closeWindow">关闭</NButton>
      </NSpace>
    </div>

    <NSpin :show="loading" class="editor-body flex-1 min-h-0 p-[12px]">
      <NResult v-if="error" status="error" title="无法读取文件" :description="error">
        <template #footer>
          <NButton @click="loadFile">重试</NButton>
        </template>
      </NResult>

      <div v-else ref="editorContainer" class="h-full min-h-0 overflow-hidden" />
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
          <NButton @click="resetEditorSettings">恢复默认</NButton>
          <NButton type="primary" @click="applyEditorSettings">完成</NButton>
        </NSpace>
      </NSpace>
    </NModal>
  </div>
</template>

<style scoped>
.editor-body :deep(.n-spin-body),
.editor-body :deep(.n-spin-content) {
  height: 100%;
  min-height: 0;
}
</style>

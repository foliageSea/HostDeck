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

const editorTheme = computed(() => (settingsStore.isDark ? 'vs-dark' : 'vs'))

const surfaceClass = computed(() => (
  settingsStore.isDark
    ? 'border-[rgba(148,163,184,0.14)] bg-[rgba(2,6,23,0.46)]'
    : 'border-[rgba(148,163,184,0.2)] bg-[rgba(255,255,255,0.74)]'
))

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
    theme: editorTheme.value,
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

watch(
  () => settingsStore.isDark,
  () => {
    monaco.editor.setTheme(editorTheme.value)
  },
)
</script>

<template>
  <div
    class="text-editor-view relative flex h-full flex-col gap-[12px] overflow-hidden p-[12px]"
    :class="settingsStore.isDark ? 'bg-[linear-gradient(180deg,rgba(15,23,42,0.18),rgba(15,23,42,0.06))]' : 'bg-[linear-gradient(180deg,rgba(255,255,255,0.7),rgba(226,232,240,0.36))]'"
  >
    <div
      class="relative z-[1] flex shrink-0 items-center justify-between gap-[12px] rounded-[18px] border px-[14px] py-[12px] shadow-[0_14px_36px_rgba(15,23,42,0.12)] backdrop-blur-[12px]"
      :class="settingsStore.isDark ? 'border-[rgba(148,163,184,0.14)] bg-transparent text-[#e2e8f0]' : 'border-[rgba(148,163,184,0.2)] bg-transparent text-[#1e293b]'"
    >
      <div class="flex min-w-0 flex-col gap-[4px]">
        <strong>{{ filename }}</strong>
        <span
          class="truncate-line text-[12px]"
          :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.9)]' : 'text-[rgba(71,85,105,0.88)]'"
        >{{ props.path }}</span>
      </div>

      <NSpace>
        <NButton round @click="showSettings = true">设置</NButton>
        <NButton round @click="loadFile">重新加载</NButton>
        <NButton round type="primary" :loading="saving" @click="saveFile">保存</NButton>
        <NButton round quaternary @click="closeWindow">关闭</NButton>
      </NSpace>
    </div>

    <NSpin :show="loading" class="editor-body relative z-[1] flex-1 min-h-0">
      <NResult v-if="error" status="error" title="无法读取文件" :description="error">
        <template #footer>
          <NButton round @click="loadFile">重试</NButton>
        </template>
      </NResult>

      <div
        v-else
        class="editor-surface h-full min-h-0 overflow-hidden rounded-[18px] border shadow-[0_20px_48px_rgba(15,23,42,0.16)]"
        :class="surfaceClass"
      >
        <div ref="editorContainer" class="h-full min-h-0 overflow-hidden rounded-[inherit]" />
      </div>
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

.editor-surface {
  backdrop-filter: blur(18px);
}
</style>

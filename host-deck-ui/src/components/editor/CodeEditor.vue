<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import * as monaco from 'monaco-editor'
import { useSettingsStore } from '@/stores/settings'

const props = withDefaults(defineProps<{
  modelValue: string
  language?: string
  readonly?: boolean
}>(), {
  language: 'plaintext',
  readonly: false,
})

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

const settingsStore = useSettingsStore()
const editorContainer = ref<HTMLElement | null>(null)

let editor: monaco.editor.IStandaloneCodeEditor | null = null
let model: monaco.editor.ITextModel | null = null
let syncDisposable: monaco.IDisposable | null = null

const editorTheme = computed(() => (settingsStore.isDark ? 'vs-dark' : 'vs'))

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

async function initEditor() {
  await nextTick()

  if (!editorContainer.value || editor) {
    return
  }

  model = monaco.editor.createModel(props.modelValue, props.language)
  editor = monaco.editor.create(editorContainer.value, {
    model,
    automaticLayout: true,
    minimap: { enabled: false },
    fontSize: settingsStore.editorFontSize,
    fontFamily: settingsStore.editorFontFamily,
    scrollBeyondLastLine: false,
    wordWrap: 'off',
    tabSize: 2,
    readOnly: props.readonly,
    theme: editorTheme.value,
  })

  syncDisposable = editor.onDidChangeModelContent(() => {
    emit('update:modelValue', editor?.getValue() ?? '')
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

onMounted(() => {
  void initEditor()
})

onBeforeUnmount(() => {
  disposeEditor()
})

watch(
  () => props.modelValue,
  (value) => {
    syncEditorContent(value)
  },
)

watch(
  () => props.language,
  (value) => {
    if (model) {
      monaco.editor.setModelLanguage(model, value)
    }
  },
)

watch(
  () => props.readonly,
  (value) => {
    editor?.updateOptions({ readOnly: value })
  },
)

watch(
  () => settingsStore.editorFontSize,
  (value) => {
    updateEditorFontOptions({ fontSize: value })
  },
)

watch(
  () => settingsStore.editorFontFamily,
  (value) => {
    updateEditorFontOptions({ fontFamily: value })
  },
)

watch(
  () => settingsStore.isDark,
  () => {
    monaco.editor.setTheme(editorTheme.value)
  },
)
</script>

<template>
  <div class="code-editor h-full min-h-0 overflow-hidden rounded-[18px] border shadow-[0_20px_48px_rgba(15,23,42,0.16)]" :class="settingsStore.isDark ? 'border-[rgba(148,163,184,0.14)] bg-[rgba(2,6,23,0.46)]' : 'border-[rgba(148,163,184,0.2)] bg-[rgba(255,255,255,0.74)]'">
    <div ref="editorContainer" class="h-full min-h-0 overflow-hidden rounded-[inherit]" />
  </div>
</template>

<style scoped>
.code-editor {
  backdrop-filter: blur(18px);
}
</style>

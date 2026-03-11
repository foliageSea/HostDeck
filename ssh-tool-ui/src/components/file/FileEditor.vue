<template>
  <div class="h-full flex flex-col bg-white dark:bg-gray-900 text-gray-900 dark:text-gray-100">
    <div class="flex items-center justify-between p-2 border-b border-gray-200 dark:border-gray-700">
      <h3 class="font-semibold text-sm">{{ filename }}</h3>
      <div class="flex gap-2">
        <button @click="save" class="bg-blue-500 hover:bg-blue-600 text-white px-3 py-1 rounded text-sm transition-colors">
          保存
        </button>
        <button @click="$emit('close')" class="bg-gray-200 hover:bg-gray-300 dark:bg-gray-700 dark:hover:bg-gray-600 text-gray-700 dark:text-gray-200 px-3 py-1 rounded text-sm transition-colors">
          关闭
        </button>
      </div>
    </div>
    <div ref="editorContainer" class="flex-1 overflow-hidden"></div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue'
import * as monaco from 'monaco-editor'

const props = defineProps<{
  filename: string
  content: string
  language?: string
}>()

const emit = defineEmits(['close', 'save'])
const editorContainer = ref<HTMLElement>()
let editor: monaco.editor.IStandaloneCodeEditor

onMounted(() => {
  if (editorContainer.value) {
    editor = monaco.editor.create(editorContainer.value, {
      value: props.content,
      language: props.language || 'plaintext',
      theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'vs-dark' : 'vs',
      automaticLayout: true,
      minimap: { enabled: true },
      scrollBeyondLastLine: false,
      fontSize: 14
    })

    // Add save command (Ctrl+S / Cmd+S)
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => {
      save()
    })
  }
})

onUnmounted(() => {
  editor?.dispose()
})

const save = () => {
  emit('save', editor.getValue())
}
</script>

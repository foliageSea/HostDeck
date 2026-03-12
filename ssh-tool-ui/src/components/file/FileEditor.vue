<template>
  <div class="h-full flex flex-col bg-background text-foreground">
    <div class="flex items-center justify-between p-2 border-b">
      <h3 class="font-semibold text-sm">{{ filename }}</h3>
      <div class="flex gap-2">
        <Button @click="save" size="sm">保存</Button>
        <Button @click="$emit('close')" variant="secondary" size="sm">关闭</Button>
      </div>
    </div>
    <div ref="editorContainer" class="flex-1 overflow-hidden"></div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import * as monaco from 'monaco-editor'
import { Button } from '@/components/ui/button'

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
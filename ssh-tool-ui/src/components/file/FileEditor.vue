<template>
  <div class="h-full flex flex-col bg-background text-foreground">
    <div class="flex items-center justify-between p-2 border-b">
      <h3 class="font-semibold text-sm">{{ filename }}</h3>
      <div class="flex gap-2">
        <DropdownMenu>
          <DropdownMenuTrigger as-child>
            <Button variant="ghost" size="icon" class="h-8 w-8">
              <Settings class="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" class=" z-[9999]">
            <DropdownMenuLabel>编辑器设置</DropdownMenuLabel>
            <DropdownMenuSeparator />

            <DropdownMenuSub>
              <DropdownMenuSubTrigger>
                <span>字体大小</span>
              </DropdownMenuSubTrigger>
              <DropdownMenuSubContent>
                <DropdownMenuRadioGroup v-model="fontSizeString">
                  <DropdownMenuRadioItem v-for="size in fontSizes" :key="size" :value="String(size)">
                    {{ size }}px
                  </DropdownMenuRadioItem>
                </DropdownMenuRadioGroup>
              </DropdownMenuSubContent>
            </DropdownMenuSub>

            <DropdownMenuSub>
              <DropdownMenuSubTrigger>
                <span>字体样式</span>
              </DropdownMenuSubTrigger>
              <DropdownMenuSubContent>
                <DropdownMenuRadioGroup v-model="editorSettings.fontFamily">
                  <DropdownMenuRadioItem v-for="font in fontFamilies" :key="font.value" :value="font.value">
                    {{ font.label }}
                  </DropdownMenuRadioItem>
                </DropdownMenuRadioGroup>
              </DropdownMenuSubContent>
            </DropdownMenuSub>
          </DropdownMenuContent>
        </DropdownMenu>

        <Button @click="save" size="sm">保存</Button>
        <Button @click="$emit('close')" variant="secondary" size="sm">关闭</Button>
      </div>
    </div>
    <div ref="editorContainer" class="flex-1 overflow-hidden"></div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, computed } from 'vue'
import * as monaco from 'monaco-editor'
import { Button } from '@/components/ui/button'
import { Settings } from 'lucide-vue-next'
import { useStorage } from '@vueuse/core'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSeparator,
  DropdownMenuLabel,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
} from '@/components/ui/dropdown-menu'

const props = defineProps<{
  filename: string
  content: string
  language?: string
}>()

const emit = defineEmits(['close', 'save'])
const editorContainer = ref<HTMLElement>()
let editor: monaco.editor.IStandaloneCodeEditor

const fontSizes = [12, 13, 14, 15, 16, 18, 20, 24]
const fontFamilies = [
  { label: 'Default', value: 'Consolas, "Courier New", monospace' },
  { label: 'Fira Code', value: '"Fira Code", monospace' },
  { label: 'JetBrains Mono', value: '"JetBrains Mono", monospace' },
  { label: 'Source Code Pro', value: '"Source Code Pro", monospace' },
]

const editorSettings = useStorage('editor-settings', {
  fontSize: 14,
  fontFamily: 'Consolas, "Courier New", monospace'
})

const fontSizeString = computed({
  get: () => String(editorSettings.value.fontSize),
  set: (val) => editorSettings.value.fontSize = Number(val)
})

watch(editorSettings, (newSettings) => {
  if (editor) {
    editor.updateOptions({
      fontSize: newSettings.fontSize,
      fontFamily: newSettings.fontFamily
    })
  }
}, { deep: true })

onMounted(() => {
  if (editorContainer.value) {
    editor = monaco.editor.create(editorContainer.value, {
      value: props.content,
      language: props.language || 'plaintext',
      theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'vs-dark' : 'vs',
      automaticLayout: true,
      minimap: { enabled: true },
      scrollBeyondLastLine: false,
      fontSize: editorSettings.value.fontSize,
      fontFamily: editorSettings.value.fontFamily
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
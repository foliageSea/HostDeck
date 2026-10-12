<script setup lang="ts">
import { onBeforeUnmount, ref } from 'vue'
import { useDesktop } from '@host-deck/webos'

const props = defineProps<{ windowId: string }>()
const desktop = useDesktop()
const text = ref('')
const saved = ref('')
desktop.setWindowBeforeClose(
  props.windowId,
  () => text.value === saved.value || window.confirm('有未保存内容，仍然关闭？'),
)
onBeforeUnmount(() => desktop.setWindowBeforeClose(props.windowId))
</script>
<template>
  <article style="padding: 24px; height: 100%; display: flex; flex-direction: column; gap: 12px">
    <label for="demo-editor">关闭时会检查未保存内容</label
    ><textarea id="demo-editor" v-model="text" style="flex: 1; resize: none" /><button
      type="button"
      @click="saved = text"
    >
      保存
    </button>
  </article>
</template>

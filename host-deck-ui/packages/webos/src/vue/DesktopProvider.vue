<script setup lang="ts">
import { onBeforeUnmount } from 'vue'
import type { DesktopContext } from './context'
import { provideDesktopContext } from './context'

const props = defineProps<{ context: DesktopContext; disposeOnUnmount?: boolean }>()
provideDesktopContext(props.context)
onBeforeUnmount(() => {
  if (props.disposeOnUnmount) props.context.desktop.dispose()
})
</script>

<template><slot /></template>

<script setup lang="ts">
import { onBeforeUnmount, onMounted, watchEffect } from 'vue'
import { useDialog, useLoadingBar, useMessage, useNotification } from 'naive-ui'
import { installUiApi } from '@/lib/ui'
import { initializePwa } from '@/lib/pwa'

const dialog = useDialog()
const loadingBar = useLoadingBar()
const message = useMessage()
const notification = useNotification()

watchEffect(() => {
  installUiApi({ dialog, loadingBar, message, notification })
})

let disposePwa: (() => void) | undefined
onMounted(() => {
  disposePwa = initializePwa()
})
onBeforeUnmount(() => disposePwa?.())
</script>

<template>
  <span style="display: none" aria-hidden="true" />
</template>

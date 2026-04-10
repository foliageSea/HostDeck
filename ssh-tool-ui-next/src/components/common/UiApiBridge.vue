<script setup lang="ts">
import { watchEffect } from 'vue'
import { useDialog, useLoadingBar, useMessage, useNotification } from 'naive-ui'
import { installUiApi } from '@/lib/ui'

const dialog = useDialog()
const loadingBar = useLoadingBar()
const message = useMessage()
const notification = useNotification()

watchEffect(() => {
  installUiApi({ dialog, loadingBar, message, notification })
})
</script>

<template>
  <span style="display: none" aria-hidden="true" />
</template>

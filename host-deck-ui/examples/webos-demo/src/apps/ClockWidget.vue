<script setup lang="ts">
import { onBeforeUnmount, ref } from 'vue'
const now = ref(new Date())
const timer = window.setInterval(() => (now.value = new Date()), 1000)
onBeforeUnmount(() => window.clearInterval(timer))
</script>
<template>
  <div style="padding: 20px; font-size: 24px">{{ now.toLocaleTimeString() }}</div>
</template>

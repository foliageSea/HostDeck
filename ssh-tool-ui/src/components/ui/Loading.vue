<template>
  <div v-if="loading" class="absolute inset-0 bg-background/80 backdrop-blur-sm flex items-center justify-center z-50">
    <Loader2 class="h-10 w-10 animate-spin text-primary" />
  </div>
</template>

<script setup lang="ts">
import { Loader2 } from 'lucide-vue-next'

defineProps<{
  loading: boolean
}>()
</script>
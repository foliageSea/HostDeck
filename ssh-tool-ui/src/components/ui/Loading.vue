<template>
  <div v-if="loading" class="absolute inset-0 bg-gray-900 bg-opacity-50 flex items-center justify-center z-50">
    <div class="animate-spin rounded-full h-10 w-10 border-t-2 border-b-2 border-white"></div>
  </div>
</template>

<script setup lang="ts">
defineProps<{
  loading: boolean
}>()
</script>

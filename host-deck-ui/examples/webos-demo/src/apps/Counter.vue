<script setup lang="ts">
import { ref } from 'vue'
const count = ref(0)
</script>
<template>
  <article style="padding: 24px">
    <h2>多实例计数器</h2>
    <button type="button" @click="count++">计数：{{ count }}</button>
  </article>
</template>

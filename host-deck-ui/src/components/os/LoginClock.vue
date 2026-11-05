<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

const now = ref(new Date())
const dateFormatter = new Intl.DateTimeFormat('zh-CN', {
  month: 'long',
  day: 'numeric',
  weekday: 'long',
})
const timeFormatter = new Intl.DateTimeFormat('zh-CN', {
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
})
const date = computed(() => dateFormatter.format(now.value))
const time = computed(() => timeFormatter.format(now.value))
let timer: number | undefined

function update() {
  now.value = new Date()
  timer = window.setTimeout(update, 60_000 - (Date.now() % 60_000))
}

function handleVisibilityChange() {
  if (document.hidden) return
  window.clearTimeout(timer)
  update()
}

onMounted(() => {
  update()
  document.addEventListener('visibilitychange', handleVisibilityChange)
})
onBeforeUnmount(() => {
  window.clearTimeout(timer)
  document.removeEventListener('visibilitychange', handleVisibilityChange)
})
</script>

<template>
  <div class="login-clock">
    <div class="login-clock-date">{{ date }}</div>
    <time class="login-clock-time" :datetime="now.toISOString()">{{ time }}</time>
  </div>
</template>

<style scoped>
.login-clock {
  text-align: center;
  user-select: none;
  text-shadow: 0 2px 24px rgba(0, 0, 0, 0.16);
}
.login-clock-date {
  font-size: clamp(17px, 2.5vw, 24px);
  font-weight: 500;
  letter-spacing: 0.02em;
}
.login-clock-time {
  display: block;
  font-family: Inter, 'Segoe UI', system-ui, sans-serif;
  font-size: clamp(80px, 13vw, 148px);
  font-weight: 650;
  line-height: 1.05;
  letter-spacing: -0.055em;
  font-variant-numeric: tabular-nums;
}
</style>

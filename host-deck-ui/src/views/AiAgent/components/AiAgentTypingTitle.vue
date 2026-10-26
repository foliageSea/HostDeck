<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'

const props = withDefaults(
  defineProps<{
    text: string
    /** 每个字符之间的间隔，毫秒 */
    speed?: number
    /** 开始打字前的停顿，毫秒 */
    delay?: number
    /** 打完一轮后停留的时间，毫秒，之后重新开始 */
    hold?: number
  }>(),
  {
    speed: 90,
    delay: 260,
    hold: 2400,
  },
)

const visibleCount = ref(0)
const typing = ref(false)
const visibleText = computed(() => props.text.slice(0, visibleCount.value))

let timer: ReturnType<typeof setTimeout> | undefined
// 系统开启“减少动态效果”时直接展示完整文字，不循环
let instant = false

function clearTimer() {
  if (timer === undefined) return
  clearTimeout(timer)
  timer = undefined
}

function typeNext() {
  timer = undefined
  if (visibleCount.value >= props.text.length) {
    holdThenRestart()
    return
  }
  visibleCount.value += 1
  if (visibleCount.value >= props.text.length) {
    holdThenRestart()
    return
  }
  timer = setTimeout(typeNext, props.speed)
}

function holdThenRestart() {
  timer = setTimeout(start, props.hold)
}

function start() {
  clearTimer()
  if (instant) {
    visibleCount.value = props.text.length
    typing.value = false
    return
  }
  visibleCount.value = 0
  typing.value = Boolean(props.text)
  if (!props.text) return
  timer = setTimeout(typeNext, props.delay)
}

onMounted(() => {
  instant =
    typeof window !== 'undefined' &&
    typeof window.matchMedia === 'function' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches
  start()
})

watch(
  () => props.text,
  () => start(),
)

onBeforeUnmount(clearTimer)
</script>

<template>
  <h1 class="agent-typing-title" :aria-label="text">
    <span class="agent-typing-text" aria-hidden="true">{{ visibleText }}</span>
    <span v-if="typing" class="agent-typing-caret" aria-hidden="true" />
  </h1>
</template>

<style scoped>
.agent-typing-caret {
  display: inline-block;
  width: 0.09em;
  min-width: 2px;
  height: 0.95em;
  margin-left: 0.08em;
  border-radius: 1px;
  background: currentColor;
  vertical-align: -0.08em;
  animation: agent-typing-caret-blink 1.05s steps(1, end) infinite;
}

@keyframes agent-typing-caret-blink {
  0%,
  55% {
    opacity: 1;
  }

  56%,
  100% {
    opacity: 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .agent-typing-caret {
    display: none;
  }
}
</style>

<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    color: string
    values: number[]
    max?: number
  }>(),
  {
    max: 100,
  },
)

const viewWidth = 160
const viewHeight = 44
const points = computed(() => {
  if (props.values.length === 0) {
    return ''
  }

  const maxValue = Math.max(1, props.max)
  const denominator = Math.max(1, props.values.length - 1)
  return props.values
    .map((value, index) => {
      const x = (index / denominator) * viewWidth
      const normalized = Math.min(maxValue, Math.max(0, value)) / maxValue
      const y = viewHeight - normalized * (viewHeight - 4) - 2
      return `${x.toFixed(1)},${y.toFixed(1)}`
    })
    .join(' ')
})
const areaPoints = computed(() =>
  points.value ? `${points.value} ${viewWidth},${viewHeight - 1} 0,${viewHeight - 1}` : '',
)
</script>

<template>
  <svg
    class="block h-full w-full overflow-visible"
    :viewBox="`0 0 ${viewWidth} ${viewHeight}`"
    preserveAspectRatio="none"
    aria-hidden="true"
  >
    <line
      x1="0"
      :y1="viewHeight - 1"
      :x2="viewWidth"
      :y2="viewHeight - 1"
      stroke="currentColor"
      stroke-opacity="0.12"
    />
    <polygon
      v-if="areaPoints"
      :points="areaPoints"
      :fill="color"
      fill-opacity="0.16"
    />
    <polyline
      v-if="points"
      :points="points"
      fill="none"
      :stroke="color"
      stroke-width="2.4"
      stroke-linecap="round"
      stroke-linejoin="round"
      vector-effect="non-scaling-stroke"
    />
  </svg>
</template>

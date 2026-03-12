<template>
  <div v-if="visible" 
    :style="{ top: y + 'px', left: x + 'px' }"
    class="fixed z-[10000] min-w-[12rem] overflow-hidden rounded-md border bg-popover p-1 text-popover-foreground shadow-md animate-in fade-in-0 zoom-in-95 select-none"
    @click.stop
  >
    <div v-for="(item, index) in items" :key="index">
      <div v-if="item.separator" class="-mx-1 my-1 h-px bg-muted"></div>
      <div v-else
        @click="handleClick(item)"
        class="relative flex cursor-default select-none items-center rounded-sm px-2 py-1.5 text-sm outline-none transition-colors hover:bg-accent hover:text-accent-foreground data-[disabled]:pointer-events-none data-[disabled]:opacity-50"
      >
        <component :is="item.icon" class="mr-2 h-4 w-4" />
        <span class="flex-1">{{ item.label }}</span>
      </div>
    </div>
  </div>
  <!-- Overlay to close menu on click outside -->
  <div v-if="visible" class="fixed inset-0 z-[9999]" @click="$emit('close')"></div>
</template>

<script setup lang="ts">
import { type Component } from 'vue'

export interface MenuItem {
  label: string
  icon?: Component
  action?: () => void
  separator?: boolean
}

defineProps<{
  visible: boolean
  x: number
  y: number
  items: MenuItem[]
}>()

const emit = defineEmits(['close'])

const handleClick = (item: MenuItem) => {
  if (item.action) {
    item.action()
  }
  emit('close')
}
</script>
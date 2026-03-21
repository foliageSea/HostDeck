<template>
  <Teleport to="body">
    <!-- Overlay to close menu on click outside -->
    <div v-if="visible" class="fixed inset-0 z-[9999]" @click="$emit('close')" @contextmenu.prevent="$emit('close')"></div>
    
    <div v-if="visible" 
      ref="menuRef"
      :style="menuStyle"
      class="fixed z-[10000] min-w-[12rem] overflow-hidden rounded-md border bg-popover p-1 text-popover-foreground shadow-md animate-in fade-in-0 zoom-in-95 select-none"
      @click.stop
      @contextmenu.prevent
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
  </Teleport>
</template>

<script setup lang="ts">
import { type Component, ref, computed, watch, nextTick } from 'vue'

export interface MenuItem {
  label: string
  icon?: Component
  action?: () => void
  separator?: boolean
}

const props = defineProps<{
  visible: boolean
  x: number
  y: number
  items: MenuItem[]
}>()

const emit = defineEmits(['close'])

const menuRef = ref<HTMLElement | null>(null)
const adjustedX = ref(0)
const adjustedY = ref(0)

watch([() => props.visible, () => props.x, () => props.y], async ([newVisible]) => {
  if (newVisible) {
    adjustedX.value = props.x
    adjustedY.value = props.y
    
    await nextTick()
    
    if (menuRef.value) {
      const rect = menuRef.value.getBoundingClientRect()
      const viewportWidth = window.innerWidth
      const viewportHeight = window.innerHeight
      
      let newX = props.x
      let newY = props.y
      
      if (newX + rect.width > viewportWidth) {
        newX = viewportWidth - rect.width - 5
      }
      
      if (newY + rect.height > viewportHeight) {
        newY = viewportHeight - rect.height - 5
      }
      
      adjustedX.value = Math.max(5, newX)
      adjustedY.value = Math.max(5, newY)
    }
  }
})

const menuStyle = computed(() => ({
  top: adjustedY.value + 'px',
  left: adjustedX.value + 'px'
}))

const handleClick = (item: MenuItem) => {
  if (item.action) {
    item.action()
  }
  emit('close')
}
</script>
<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { DropdownMenuContent, DropdownMenuPortal, DropdownMenuRoot } from 'reka-ui'
import { useDesktopContext } from './context'
import DesktopMenuItems from './DesktopMenuItems.vue'
import type { DesktopMenuOption } from './menu-options'

const props = defineProps<{
  show: boolean
  x: number
  y: number
  options: DesktopMenuOption[]
}>()
const emit = defineEmits<{ close: []; select: [key: string] }>()
const context = useDesktopContext()
const reference = computed(() => ({
  getBoundingClientRect: () => new DOMRect(props.x, props.y, 0, 0),
}))
let previousFocus: HTMLElement | null = null
const interactedOutside = ref(false)

watch(
  () => props.show,
  (show) => {
    if (show) {
      previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null
      interactedOutside.value = false
    }
  },
  { immediate: true },
)

function restoreFocus(event: Event) {
  event.preventDefault()
  if (!interactedOutside.value && previousFocus?.isConnected) {
    previousFocus.focus({ preventScroll: true })
  }
}
</script>

<template>
  <DropdownMenuRoot :open="show" :modal="false" @update:open="!$event && emit('close')">
    <DropdownMenuPortal
      :to="context.overlayTarget?.value ?? undefined"
      :disabled="!context.overlayTarget?.value"
    >
      <DropdownMenuContent
        class="webos-context-menu webos-menu-surface min-w-[160px] rounded-[10px] p-[4px] outline-none"
        aria-label="操作菜单"
        :reference="reference"
        side="bottom"
        align="start"
        position-strategy="fixed"
        :collision-boundary="context.overlayTarget?.value"
        :collision-padding="8"
        loop
        @interact-outside="interactedOutside = true"
        @close-auto-focus="restoreFocus"
      >
        <DesktopMenuItems :options="options" @select="emit('select', $event)" />
      </DropdownMenuContent>
    </DropdownMenuPortal>
  </DropdownMenuRoot>
</template>

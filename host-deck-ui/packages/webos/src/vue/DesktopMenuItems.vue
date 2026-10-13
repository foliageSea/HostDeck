<script setup lang="ts">
import { ChevronRight } from '@lucide/vue'
import {
  DropdownMenuItem,
  DropdownMenuPortal,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
} from 'reka-ui'
import { useDesktopContext } from './context'
import type { DesktopMenuOption } from './menu-options'

defineProps<{ options: DesktopMenuOption[] }>()
defineEmits<{ select: [key: string] }>()
const context = useDesktopContext()
</script>

<template>
  <template v-for="option in options" :key="option.key">
    <DropdownMenuSub v-if="option.children">
      <DropdownMenuSubTrigger
        class="webos-menu-item flex items-center justify-between gap-[16px] rounded-[6px] px-[10px] py-[6px] text-[13px] outline-none"
        :disabled="option.disabled || option.children.length === 0"
        :text-value="option.label"
      >
        {{ option.label }}
        <ChevronRight :size="14" aria-hidden="true" />
      </DropdownMenuSubTrigger>
      <DropdownMenuPortal
        :to="context.overlayTarget?.value ?? undefined"
        :disabled="!context.overlayTarget?.value"
      >
        <DropdownMenuSubContent
          class="webos-context-menu webos-menu-surface min-w-[160px] rounded-[10px] p-[4px] outline-none"
          :collision-boundary="context.overlayTarget?.value"
          :collision-padding="8"
          :side-offset="4"
          loop
        >
          <DesktopMenuItems :options="option.children" @select="$emit('select', $event)" />
        </DropdownMenuSubContent>
      </DropdownMenuPortal>
    </DropdownMenuSub>
    <DropdownMenuItem
      v-else
      class="webos-menu-item flex items-center rounded-[6px] px-[10px] py-[6px] text-[13px] outline-none"
      :class="{ 'webos-danger': option.danger }"
      :disabled="option.disabled"
      :text-value="option.label"
      @select="$emit('select', option.key)"
    >
      {{ option.label }}
    </DropdownMenuItem>
  </template>
</template>

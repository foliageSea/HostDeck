<script setup lang="ts">
import {
  TooltipContent,
  TooltipPortal,
  TooltipProvider,
  TooltipRoot,
  TooltipTrigger,
} from 'reka-ui'
import { useDesktopContext } from './context'

const context = useDesktopContext()
</script>

<template>
  <TooltipProvider :delay-duration="300" ignore-non-keyboard-focus>
    <TooltipRoot>
      <TooltipTrigger as-child><slot name="trigger" /></TooltipTrigger>
      <TooltipPortal
        :to="context.overlayTarget?.value ?? undefined"
        :disabled="!context.overlayTarget?.value"
      >
        <TooltipContent
          class="webos-tooltip rounded-[8px] px-[10px] py-[6px] text-[12px]"
          side="top"
          :side-offset="8"
          :collision-boundary="context.overlayTarget?.value"
          :collision-padding="8"
        >
          <slot />
        </TooltipContent>
      </TooltipPortal>
    </TooltipRoot>
  </TooltipProvider>
</template>

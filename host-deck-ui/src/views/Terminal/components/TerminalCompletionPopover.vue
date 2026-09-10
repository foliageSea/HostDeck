<script setup lang="ts">
import { nextTick, ref, watch, type CSSProperties } from 'vue'
import type { TerminalCompletionItem } from '../completion/terminalCompletion'

const props = defineProps<{
  activeIndex: number
  anchorStyle: CSSProperties
  dark: boolean
  items: TerminalCompletionItem[]
  visible: boolean
}>()

const emit = defineEmits<{
  hover: [index: number]
  select: [item: TerminalCompletionItem]
}>()

const listElement = ref<HTMLElement | null>(null)
const sourceLabels = {
  command: '命令',
  history: '历史',
  snippet: '片段',
} as const

watch(
  () => props.activeIndex,
  async (index) => {
    await nextTick()
    listElement.value
      ?.querySelector<HTMLElement>(`[data-completion-index="${index}"]`)
      ?.scrollIntoView({
        block: 'nearest',
      })
  },
)
</script>

<template>
  <Teleport to="body">
    <div
      v-if="visible"
      ref="listElement"
      class="terminal-completion fixed z-[10000] w-[min(380px,calc(100vw-24px))] overflow-hidden rounded-[10px] border shadow-[0_16px_48px_rgba(2,6,23,0.38)] backdrop-blur-[18px]"
      :class="
        dark
          ? 'border-[rgba(100,116,139,0.28)] bg-[rgba(8,15,31,0.97)] text-slate-100'
          : 'border-[rgba(148,163,184,0.35)] bg-[rgba(255,255,255,0.97)] text-slate-800'
      "
      :style="anchorStyle"
      role="listbox"
      aria-label="终端命令补全"
      @mousedown.prevent.stop
    >
      <div class="terminal-completion-list max-h-[232px] overflow-y-auto p-[5px]">
        <button
          v-for="(item, index) in items"
          :key="item.id"
          type="button"
          role="option"
          class="relative flex w-full appearance-none items-center gap-[9px] border-0 bg-transparent px-[9px] py-[7px] text-left text-inherit outline-none transition-colors duration-100 rounded-[6px] cursor-pointer"
          :class="[
            index === activeIndex
              ? dark
                ? 'bg-[rgba(37,99,235,0.42)] text-white shadow-[inset_0_0_0_1px_rgba(96,165,250,0.42)] before:absolute before:bottom-[6px] before:left-[2px] before:top-[6px] before:w-[3px] before:rounded-full before:bg-blue-400'
                : 'bg-[rgba(37,99,235,0.17)] text-blue-950 shadow-[inset_0_0_0_1px_rgba(37,99,235,0.3)] before:absolute before:bottom-[6px] before:left-[2px] before:top-[6px] before:w-[3px] before:rounded-full before:bg-blue-600'
              : dark
                ? 'hover:bg-[rgba(51,65,85,0.42)]'
                : 'hover:bg-[rgba(226,232,240,0.62)]',
          ]"
          :aria-selected="index === activeIndex"
          :data-completion-index="index"
          @mouseenter="emit('hover', index)"
          @click="emit('select', item)"
        >
          <span
            class="h-[6px] w-[6px] shrink-0 rounded-full"
            :class="{
              'bg-cyan-400': item.source === 'snippet',
              'bg-amber-400': item.source === 'history',
              'bg-blue-400': item.source === 'command',
            }"
          />
          <span
            class="min-w-0 flex-1 truncate font-mono text-[13px] leading-[18px]"
            :class="index === activeIndex ? 'font-600' : ''"
          >
            {{ item.command }}
          </span>
          <span v-if="item.detail" class="max-w-[105px] truncate text-[11px] opacity-55">
            {{ item.detail }}
          </span>
          <span class="shrink-0 text-[10px] opacity-38">
            {{ sourceLabels[item.source] }}
          </span>
        </button>
      </div>
      <div
        class="flex items-center justify-between border-t px-[12px] py-[6px] text-[10px]"
        :class="dark ? 'border-[rgba(100,116,139,0.2)]' : 'border-[rgba(148,163,184,0.25)]'"
      >
        <span class="opacity-38">命令补全</span>
        <div class="flex gap-[10px] opacity-45">
          <span><kbd>↑↓</kbd> 选择</span>
          <span><kbd>Tab</kbd> 填入</span>
          <span><kbd>↵</kbd> 执行</span>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.terminal-completion-list {
  scrollbar-color: rgba(100, 116, 139, 0.45) transparent;
  scrollbar-width: thin;
}

.terminal-completion-list::-webkit-scrollbar {
  width: 5px;
}

.terminal-completion-list::-webkit-scrollbar-thumb {
  border-radius: 999px;
  background: rgba(100, 116, 139, 0.45);
}

kbd {
  font: inherit;
  font-weight: 600;
}
</style>

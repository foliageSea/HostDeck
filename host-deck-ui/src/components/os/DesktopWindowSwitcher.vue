<script setup lang="ts">
import { X } from '@lucide/vue'
import { useSettingsStore } from '@/stores/settings'
import AppIcon from '@/components/common/AppIcon.vue'
import type { WindowState } from '@/stores/desktop'

const settingsStore = useSettingsStore()

defineProps<{
  selectedIndex: number
  windows: WindowState[]
}>()

defineEmits<{
  close: [id: string]
  select: [index: number]
}>()
</script>

<template>
  <div
    class="absolute inset-0 z-[99999] flex items-center justify-center backdrop-blur-[8px]"
    :class="settingsStore.isDark ? 'bg-[rgba(2,6,23,0.28)]' : 'bg-[rgba(226,232,240,0.42)]'"
  >
    <div
      class="app-radius-card min-w-[320px] max-w-[860px] rounded-[24px] p-[18px]"
      :class="[
        settingsStore.isDark
          ? 'border border-[rgba(148,163,184,0.18)] bg-[rgba(15,23,42,0.72)] shadow-[0_28px_80px_rgba(2,6,23,0.4)]'
          : 'border border-[rgba(148,163,184,0.22)] bg-[rgba(255,255,255,0.82)] shadow-[0_28px_80px_rgba(148,163,184,0.24)]',
      ]"
    >
      <div
        class="mb-[14px] text-[0.92rem]"
        :class="
          settingsStore.isDark ? 'text-[rgba(226,232,240,0.72)]' : 'text-[rgba(51,65,85,0.78)]'
        "
      >
        切换窗口
      </div>
      <div class="flex flex-wrap gap-[14px]">
        <div
          v-for="(window, index) in windows"
          :key="window.id"
          class="app-radius-card group relative w-[132px] rounded-[18px] border transition-[transform,border-color,background-color,box-shadow] duration-[200ms] ease-in-out hover:translate-y-[-2px] hover:scale-[1.06] hover:shadow-[0_18px_40px_rgba(15,23,42,0.28)]"
          :class="[
            settingsStore.isDark
              ? 'border-transparent bg-[rgba(30,41,59,0.74)] text-[#e2e8f0] hover:border-[rgba(96,165,250,0.44)] hover:bg-[rgba(51,65,85,0.92)]'
              : 'border-transparent bg-[rgba(241,245,249,0.92)] text-[#1e293b] hover:border-[rgba(59,130,246,0.34)] hover:bg-[rgba(219,234,254,0.92)]',
            selectedIndex === index
              ? settingsStore.isDark
                ? 'translate-y-[-2px] scale-[1.06] border-[rgba(96,165,250,0.44)] bg-[rgba(51,65,85,0.92)] shadow-[0_18px_40px_rgba(15,23,42,0.28)]'
                : 'translate-y-[-2px] scale-[1.06] border-[rgba(59,130,246,0.34)] bg-[rgba(219,234,254,0.92)] shadow-[0_18px_40px_rgba(15,23,42,0.28)]'
              : '',
          ]"
        >
          <button
            type="button"
            class="w-full cursor-pointer border-0 bg-transparent p-[16px_12px] text-inherit"
            @click="$emit('select', index)"
          >
            <div class="mb-[10px] flex justify-center">
              <AppIcon :name="window.icon" :size="52" themed />
            </div>
            <div class="break-words text-center text-[0.88rem]">{{ window.title }}</div>
          </button>
          <button
            type="button"
            class="absolute right-[7px] top-[7px] inline-flex h-[24px] w-[24px] cursor-pointer items-center justify-center rounded-full border-0 opacity-70 transition-[background-color,color,opacity] hover:bg-[#c42b1c] hover:text-white hover:opacity-100 focus-visible:opacity-100"
            :class="
              settingsStore.isDark
                ? 'bg-[rgba(15,23,42,0.78)] text-[rgba(226,232,240,0.88)]'
                : 'bg-[rgba(255,255,255,0.86)] text-[rgba(15,23,42,0.78)]'
            "
            :title="`关闭${window.title}`"
            :aria-label="`关闭${window.title}`"
            @click="$emit('close', window.id)"
          >
            <NIcon :size="14"><X /></NIcon>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

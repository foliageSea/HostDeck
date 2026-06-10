<script setup lang="ts">
import { useSettingsStore } from '@/stores/settings'
import AppIcon from '@/components/common/AppIcon.vue'
import type { WindowState } from '@/stores/desktop'

const settingsStore = useSettingsStore()

defineProps<{
  selectedIndex: number
  windows: WindowState[]
}>()

defineEmits<{
  select: [index: number]
}>()
</script>

<template>
  <div
    class="absolute inset-0 z-[99999] flex items-center justify-center backdrop-blur-[8px]"
    :class="settingsStore.isDark ? 'bg-[rgba(2,6,23,0.28)]' : 'bg-[rgba(226,232,240,0.42)]'"
  >
    <div
      class="min-w-[320px] max-w-[860px] rounded-[24px] p-[18px]"
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
        <button
          v-for="(window, index) in windows"
          :key="window.id"
          type="button"
          class="w-[132px] rounded-[18px] border p-[16px_12px] transition-[transform,border-color,background-color,box-shadow] duration-[200ms] ease-in-out hover:translate-y-[-2px] hover:scale-[1.06] hover:shadow-[0_18px_40px_rgba(15,23,42,0.28)] cursor-pointer"
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
          @click="$emit('select', index)"
        >
          <div class="mb-[10px] flex justify-center">
            <AppIcon :name="window.icon" :size="22" />
          </div>
          <div class="break-words text-center text-[0.88rem]">{{ window.title }}</div>
        </button>
      </div>
    </div>
  </div>
</template>

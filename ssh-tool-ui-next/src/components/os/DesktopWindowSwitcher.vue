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
  <div class="switcher-overlay" :class="{ 'switcher-overlay-light': !settingsStore.isDark }">
    <div class="switcher-panel">
      <div class="switcher-title">切换窗口</div>
      <div class="switcher-grid">
        <button
          v-for="(window, index) in windows"
          :key="window.id"
          type="button"
          class="switcher-item"
          :class="{ 'switcher-item-active': selectedIndex === index }"
          @click="$emit('select', index)"
        >
          <div class="switcher-item-icon">
            <AppIcon :name="window.icon" :size="22" />
          </div>
          <div class="switcher-item-title">{{ window.title }}</div>
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.switcher-overlay {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(2, 6, 23, 0.28);
  backdrop-filter: blur(8px);
  z-index: 40;
}

.switcher-panel {
  min-width: 320px;
  max-width: 860px;
  padding: 18px;
  border-radius: 24px;
  background: rgba(15, 23, 42, 0.72);
  border: 1px solid rgba(148, 163, 184, 0.18);
  box-shadow: 0 28px 80px rgba(2, 6, 23, 0.4);
}

.switcher-title {
  margin-bottom: 14px;
  color: rgba(226, 232, 240, 0.72);
  font-size: 0.92rem;
}

.switcher-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 14px;
}

.switcher-item {
  width: 132px;
  padding: 16px 12px;
  border-radius: 18px;
  border: 1px solid transparent;
  background: rgba(30, 41, 59, 0.74);
  color: #e2e8f0;
  cursor: pointer;
  transition: transform 0.18s ease, border-color 0.18s ease, background-color 0.18s ease;
}

.switcher-item:hover,
.switcher-item-active {
  transform: translateY(-2px) scale(1.02);
  border-color: rgba(96, 165, 250, 0.44);
  background: rgba(51, 65, 85, 0.92);
}

.switcher-item-icon {
  display: flex;
  justify-content: center;
  margin-bottom: 10px;
}

.switcher-item-title {
  font-size: 0.88rem;
  text-align: center;
}

.switcher-overlay-light {
  background: rgba(226, 232, 240, 0.42);
}

.switcher-overlay-light .switcher-panel {
  background: rgba(255, 255, 255, 0.82);
  border-color: rgba(148, 163, 184, 0.22);
  box-shadow: 0 28px 80px rgba(148, 163, 184, 0.24);
}

.switcher-overlay-light .switcher-title {
  color: rgba(51, 65, 85, 0.78);
}

.switcher-overlay-light .switcher-item {
  background: rgba(241, 245, 249, 0.92);
  color: #1e293b;
}

.switcher-overlay-light .switcher-item:hover,
.switcher-overlay-light .switcher-item-active {
  background: rgba(219, 234, 254, 0.92);
  border-color: rgba(59, 130, 246, 0.34);
}
</style>

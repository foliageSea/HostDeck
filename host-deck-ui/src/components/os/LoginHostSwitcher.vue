<script setup lang="ts">
import { ref } from 'vue'
import { Check, ChevronDown, Plus, Server } from '@lucide/vue'
import type { SavedServer } from '@/api/server'
import { useSettingsStore } from '@/stores/settings'

defineProps<{
  servers: SavedServer[]
  selectedServer: SavedServer | null
  latencies: Record<number, { status: 'checking' | 'online' | 'offline'; value?: number }>
  disabled?: boolean
}>()
const emit = defineEmits<{ select: [server: SavedServer]; create: [] }>()
const settingsStore = useSettingsStore()
const visible = ref(false)

function select(server: SavedServer) {
  visible.value = false
  emit('select', server)
}

function avatarStyle(server: SavedServer) {
  const identity = `${server.id ?? server.host}:${server.username}`
  const hue = Array.from(identity).reduce((hash, char) => (hash * 31 + char.charCodeAt(0)) % 360, 0)
  return {
    background: `linear-gradient(145deg, hsl(${hue} 70% 76%), hsl(${(hue + 45) % 360} 55% 42%))`,
  }
}
</script>

<template>
  <NPopover
    v-if="servers.length"
    v-model:show="visible"
    trigger="click"
    placement="top"
    :show-arrow="false"
    :disabled="disabled"
    :style="{
      padding: '8px',
      borderRadius: '20px',
      maxWidth: 'calc(100vw - 32px)',
      background: settingsStore.isDark ? 'rgba(15, 23, 42, 0.78)' : 'rgba(255, 255, 255, 0.82)',
      backdropFilter: 'blur(24px)',
      border: '1px solid rgba(148, 163, 184, 0.22)',
    }"
  >
    <template #trigger>
      <button
        type="button"
        class="host-avatar-trigger"
        aria-label="切换主机"
        :aria-expanded="visible"
        :disabled="disabled"
      >
        <span class="host-avatar" :style="selectedServer ? avatarStyle(selectedServer) : undefined">
          <Server :size="34" :stroke-width="1.6" />
        </span>
        <span class="host-avatar-chevron"><ChevronDown :size="13" /></span>
      </button>
    </template>
    <div class="host-options" role="group" aria-label="选择主机">
      <button
        v-for="server in servers"
        :key="server.id ?? `${server.host}:${server.port}`"
        type="button"
        class="host-option"
        :class="{ 'host-option-selected': server.id === selectedServer?.id }"
        :aria-pressed="server.id === selectedServer?.id"
        @click="select(server)"
      >
        <span class="host-option-avatar" :style="avatarStyle(server)"><Server :size="19" /></span>
        <span class="host-option-info">
          <span class="host-option-name">{{ server.name || server.host }}</span>
          <span class="host-option-address"
            >{{ server.username }}@{{ server.host }}:{{ server.port }}</span
          >
          <span
            class="host-option-status"
            :class="`host-option-status--${latencies[server.id ?? -1]?.status ?? 'checking'}`"
          >
            {{
              latencies[server.id ?? -1]?.status === 'online'
                ? `${latencies[server.id ?? -1]?.value} ms`
                : latencies[server.id ?? -1]?.status === 'offline'
                  ? '不可达'
                  : '检测中'
            }}
          </span>
        </span>
        <Check
          v-if="server.id === selectedServer?.id"
          :size="16"
          class="shrink-0 text-[var(--app-primary-color)]"
        />
      </button>
    </div>
  </NPopover>
  <button
    v-else
    type="button"
    class="host-avatar-trigger"
    aria-label="添加主机"
    @click="emit('create')"
  >
    <span class="host-avatar host-avatar-empty"><Plus :size="34" :stroke-width="1.6" /></span>
  </button>
</template>

<style scoped>
.host-avatar-trigger {
  position: relative;
  border: 0;
  padding: 0;
  border-radius: 50%;
  background: transparent;
  color: white;
  cursor: pointer;
  transition: transform 180ms ease;
}
.host-avatar-trigger:hover {
  transform: translateY(-2px);
}
.host-avatar-trigger:focus-visible {
  outline: 3px solid white;
  outline-offset: 6px;
}
.host-avatar-trigger:disabled {
  cursor: wait;
}
.host-avatar {
  display: grid;
  width: 80px;
  height: 80px;
  place-items: center;
  border: 2px solid rgba(255, 255, 255, 0.65);
  border-radius: 50%;
  box-shadow:
    0 6px 28px rgba(0, 0, 0, 0.2),
    inset 0 0 20px rgba(255, 255, 255, 0.15);
}
.host-avatar-empty {
  background: rgba(255, 255, 255, 0.18);
  backdrop-filter: blur(18px);
}
.host-avatar-chevron {
  position: absolute;
  right: -2px;
  bottom: 0;
  display: grid;
  width: 24px;
  height: 24px;
  place-items: center;
  border: 1px solid rgba(255, 255, 255, 0.35);
  border-radius: 50%;
  background: rgba(30, 41, 59, 0.65);
  backdrop-filter: blur(12px);
}
.host-options {
  width: 320px;
  max-width: calc(100vw - 48px);
  max-height: min(340px, 45dvh);
  overflow-y: auto;
}
.host-option {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 12px;
  border: 0;
  border-radius: 12px;
  padding: 12px;
  background: transparent;
  color: inherit;
  font: inherit;
  text-align: left;
  cursor: pointer;
}
.host-option:hover,
.host-option-selected {
  background: var(--app-primary-soft);
}
.host-option:focus-visible {
  outline: 2px solid var(--app-primary-color);
  outline-offset: -2px;
}
.host-option-avatar {
  display: grid;
  width: 40px;
  height: 40px;
  flex-shrink: 0;
  place-items: center;
  border-radius: 50%;
  color: white;
}
.host-option-info {
  display: flex;
  min-width: 0;
  flex: 1;
  flex-direction: column;
  gap: 3px;
}
.host-option-name,
.host-option-address {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.host-option-name {
  font-weight: 600;
}
.host-option-address,
.host-option-status {
  font-size: 12px;
  opacity: 0.7;
}
.host-option-status--online {
  color: #16a34a;
}
.host-option-status--offline {
  color: #ef4444;
}
</style>

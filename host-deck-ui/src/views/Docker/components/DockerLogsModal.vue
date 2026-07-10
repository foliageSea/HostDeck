<script setup lang="ts">
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()
</script>

<template>
  <NModal
    v-model:show="controller.logsVisible"
    preset="card"
    :title="controller.logsTitle"
    class="logs-modal"
    style="width: min(960px, 92vw)"
  >
    <div class="mb-[12px] flex flex-col gap-[10px]">
      <div class="flex items-center gap-[10px]">
        <NInputNumber
          v-model:value="controller.logsTail"
          class="w-[112px] flex-none"
          :min="20"
          :max="5000"
          :step="20"
          placeholder="Tail"
        />
        <NInput
          v-model:value="controller.logsKeyword"
          class="min-w-0 flex-1"
          placeholder="过滤日志关键字"
          clearable
        />
      </div>
      <div class="flex flex-wrap items-center gap-[10px]">
        <NSpace>
          <NButton quaternary :loading="controller.logsRefreshing" @click="controller.refreshLogs()"
            >刷新日志</NButton
          >
          <NButton quaternary @click="controller.copyLogs">复制</NButton>
          <NButton quaternary @click="controller.downloadLogs">下载</NButton>
        </NSpace>
      </div>
    </div>
    <NSpin :show="controller.logsLoading">
      <pre
        class="app-radius-item docker-console mono-ui m-0 max-h-[65vh] overflow-auto whitespace-pre-wrap break-words rounded-[14px] p-[14px] text-[12px] leading-[1.6] app-scrollbar select-text"
        :class="
          settingsStore.isDark
            ? 'bg-[rgba(2,6,23,0.9)] text-[#dbeafe] app-scrollbar-dark'
            : 'bg-[rgba(248,250,252,0.96)] text-[rgba(30,41,59,0.96)] app-scrollbar-light'
        "
        >{{ controller.displayedLogs }}</pre
      >
    </NSpin>
    <div class="mt-[10px] flex items-center justify-between gap-[12px]">
      <span
        class="text-[12px]"
        :class="
          settingsStore.isDark ? 'text-[rgba(226,232,240,0.68)]' : 'text-[rgba(71,85,105,0.88)]'
        "
        >更新于 {{ controller.formatDateTime(controller.logsLastUpdatedAt) }}</span
      >
      <div class="flex items-center gap-[8px]">
        <span
          class="text-[12px]"
          :class="
            settingsStore.isDark ? 'text-[rgba(226,232,240,0.68)]' : 'text-[rgba(71,85,105,0.88)]'
          "
          >自动刷新</span
        >
        <NSwitch v-model:value="controller.logsAutoRefresh" />
      </div>
    </div>
  </NModal>
</template>

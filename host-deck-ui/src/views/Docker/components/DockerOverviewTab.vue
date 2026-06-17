<script setup lang="ts">
import { computed } from 'vue'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'
import DockerSummaryCards from './DockerSummaryCards.vue'
import DockerTabToolbar from './DockerTabToolbar.vue'

const props = defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()

const overviewCards = computed(() => [
  {
    label: '容器总数',
    value: props.controller.containerSummary.total,
  },
  {
    label: 'Docker 网络',
    value: props.controller.networks.length,
  },
  {
    label: '存储卷数',
    value: props.controller.volumes.length,
  },
  {
    label: '编排项目',
    value: props.controller.composeProjects.length,
  },
])

const composeStatusText = computed(() => {
  if (props.controller.composeAvailable === null) {
    return '检测中'
  }

  return props.controller.composeAvailable ? '可用' : '不可用'
})

const composeStatusType = computed(() => {
  if (props.controller.composeAvailable === null) {
    return 'default'
  }

  return props.controller.composeAvailable ? 'success' : 'warning'
})
</script>

<template>
  <div class="flex flex-col gap-[16px]">
    <NCard
      size="small"
      :bordered="false"
      class="rounded-[20px]"
      :class="
        settingsStore.isDark
          ? 'bg-[linear-gradient(145deg,rgba(15,23,42,0.78),rgba(30,41,59,0.52))]'
          : 'bg-[linear-gradient(145deg,rgba(255,255,255,0.98),rgba(241,245,249,0.94))]'
      "
    >
      <DockerTabToolbar>
        <template #left>
          <div class="text-[16px] font-600">Docker 概览</div>
        </template>

        <template #actions>
          <NButton quaternary size="small" @click="controller.confirmPruneBuildCache(false)"
            >清理构建缓存</NButton
          >
          <NButton quaternary size="small" type="error" @click="controller.confirmPruneBuildCache(true)"
            >清理全部缓存</NButton
          >
          <NButton quaternary size="small" :loading="controller.loading" @click="controller.refresh"
            >刷新</NButton
          >
        </template>

        <template #meta>
          <NTag round size="small" :type="composeStatusType">Compose {{ composeStatusText }}</NTag>
          <NTag round size="small">容器 {{ controller.containerSummary.total }}</NTag>
          <NTag round size="small">镜像 {{ controller.imageSummary.total }}</NTag>
        </template>
      </DockerTabToolbar>
    </NCard>

    <DockerSummaryCards :controller="controller" />

    <div class="grid grid-cols-4 gap-[12px] lt-md:grid-cols-2 lt-sm:grid-cols-1">
      <NCard
        v-for="card in overviewCards"
        :key="card.label"
        size="small"
        :bordered="false"
        class="rounded-[18px]"
        :class="settingsStore.isDark ? 'bg-[rgba(15,23,42,0.72)]' : 'bg-[rgba(255,255,255,0.84)]'"
      >
        <div
          class="text-[12px]"
          :class="
            settingsStore.isDark ? 'text-[rgba(226,232,240,0.68)]' : 'text-[rgba(100,116,139,0.92)]'
          "
        >
          {{ card.label }}
        </div>
        <div class="mt-[6px] text-[28px] font-700">{{ card.value }}</div>
      </NCard>
    </div>
  </div>
</template>

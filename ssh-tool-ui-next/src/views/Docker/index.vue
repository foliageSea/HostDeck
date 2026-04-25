<script setup lang="ts">
import { reactive } from 'vue'
import { Add, Cube, Download, Upload } from '@vicons/carbon'
import { useSettingsStore } from '@/stores/settings'
import DockerContainersTab from './components/DockerContainersTab.vue'
import DockerCreateContainerModal from './components/DockerCreateContainerModal.vue'
import DockerImageHistoryModal from './components/DockerImageHistoryModal.vue'
import DockerImageRefsModal from './components/DockerImageRefsModal.vue'
import DockerImageTagModal from './components/DockerImageTagModal.vue'
import DockerInspectModal from './components/DockerInspectModal.vue'
import DockerImagesTab from './components/DockerImagesTab.vue'
import DockerLogsModal from './components/DockerLogsModal.vue'
import DockerRenameContainerModal from './components/DockerRenameContainerModal.vue'
import DockerSummaryCards from './components/DockerSummaryCards.vue'
import { useDockerView, type DockerViewController } from './hooks/useDockerView'

const props = defineProps<{
  windowId?: string
  connectionId?: string
  host?: string
  username?: string
}>()

const settingsStore = useSettingsStore()
const controller: DockerViewController = reactive(useDockerView(props))
</script>

<template>
  <div
    class="flex h-full flex-col gap-[16px] overflow-auto p-[18px] app-scrollbar"
    :class="settingsStore.isDark
      ? 'bg-[linear-gradient(180deg,rgba(15,23,42,0.16),rgba(15,23,42,0.06))] app-scrollbar-dark'
      : 'bg-[linear-gradient(180deg,rgba(255,255,255,0.72),rgba(226,232,240,0.38))] app-scrollbar-light'"
  >
    <div class="flex flex-col gap-[16px]">
      <div class="flex flex-wrap items-start justify-between gap-[16px]">
        <div>
          <div class="mb-[6px] flex items-center gap-[8px]">
            <NIcon :size="20"><Cube /></NIcon>
            <h2 class="m-0 text-[20px]">Docker 管理</h2>
          </div>
          <p class="m-0" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.72)]' : 'text-[rgba(71,85,105,0.88)]'">
            查看容器与镜像状态，并执行常见运维操作。
          </p>
        </div>

        <NSpace>
          <NButton quaternary @click="controller.openCreateContainer">
            <template #icon>
              <NIcon><Add /></NIcon>
            </template>
            新建容器
          </NButton>
          <NInput
            :value="controller.pullImageName"
            class="w-[min(320px,60vw)] lt-sm:w-full"
            placeholder="例如 nginx:latest"
            @update:value="controller.pullImageName = $event"
            @keydown.enter.prevent="controller.pullImage"
          >
            <template #prefix>
              <NIcon><Download /></NIcon>
            </template>
          </NInput>
          <NButton type="primary" :loading="controller.pullingImage" @click="controller.pullImage">
            <template #icon>
              <NIcon><Upload /></NIcon>
            </template>
            拉取镜像
          </NButton>
          <NButton quaternary :loading="controller.loading" @click="controller.refresh">刷新</NButton>
        </NSpace>
      </div>

      <DockerSummaryCards :controller="controller" />
    </div>

    <NSpin :show="controller.loading" class="docker-body">
      <NResult
        v-if="controller.dockerAvailable === false"
        status="warning"
        title="当前环境不可用"
        description="该服务器未安装 Docker，或当前连接无法访问 Docker 服务。"
      />

      <NTabs
        v-else
        :value="controller.activeTab"
        type="segment"
        animated
        class="docker-tabs"
        @update:value="controller.setActiveTab"
      >
        <NTabPane name="containers" tab="容器">
          <DockerContainersTab :controller="controller" />
        </NTabPane>

        <NTabPane name="images" tab="镜像">
          <DockerImagesTab :controller="controller" />
        </NTabPane>
      </NTabs>
    </NSpin>

    <DockerLogsModal :controller="controller" />
    <DockerInspectModal :controller="controller" />
    <DockerCreateContainerModal :controller="controller" />
    <DockerRenameContainerModal :controller="controller" />
    <DockerImageTagModal :controller="controller" />
    <DockerImageHistoryModal :controller="controller" />
    <DockerImageRefsModal :controller="controller" />
  </div>
</template>

<style scoped>
.docker-body {
  flex: none;
}

.docker-body :deep(.n-spin-container),
.docker-body :deep(.n-spin-content) {
  overflow: visible;
}

.docker-body :deep(.n-spin-content) {
  display: block;
}

.docker-tabs {
  display: block;
}

.docker-tabs :deep(.n-tabs-content) {
  display: block;
  overflow: visible;
}

.docker-tabs :deep(.n-tabs-pane-wrapper),
.docker-tabs :deep(.n-tab-pane) {
  overflow: visible;
}
</style>

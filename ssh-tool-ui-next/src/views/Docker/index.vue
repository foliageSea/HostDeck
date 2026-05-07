<script setup lang="ts">
import { reactive } from 'vue'
import { useMediaQuery } from '@vueuse/core'
import { Download, Upload } from '@vicons/carbon'
import { LogoDocker } from '@vicons/ionicons5'
import { useSettingsStore } from '@/stores/settings'
import DockerContainersTab from './components/DockerContainersTab.vue'
import DockerComposeTab from './components/DockerComposeTab.vue'
import DockerImageHistoryModal from './components/DockerImageHistoryModal.vue'
import DockerImageRefsModal from './components/DockerImageRefsModal.vue'
import DockerImageTagModal from './components/DockerImageTagModal.vue'
import DockerInspectModal from './components/DockerInspectModal.vue'
import DockerImagesTab from './components/DockerImagesTab.vue'
import DockerLogsModal from './components/DockerLogsModal.vue'
import DockerNetworksTab from './components/DockerNetworksTab.vue'
import DockerOverviewTab from './components/DockerOverviewTab.vue'
import DockerRenameContainerModal from './components/DockerRenameContainerModal.vue'
import DockerVolumesTab from './components/DockerVolumesTab.vue'
import { useDockerView, type DockerViewController } from './hooks/useDockerView'

const props = defineProps<{
  windowId?: string
  connectionId?: string
  host?: string
  username?: string
}>()

const settingsStore = useSettingsStore()
const preferLeftTabs = useMediaQuery('(min-width: 768px)')
const controller: DockerViewController = reactive(useDockerView(props))
</script>

<template>
  <div
    class="flex h-full min-h-0 flex-col gap-[16px] overflow-hidden p-[18px]"
    :class="settingsStore.isDark
      ? 'bg-[linear-gradient(180deg,rgba(15,23,42,0.16),rgba(15,23,42,0.06))]'
      : 'bg-[linear-gradient(180deg,rgba(255,255,255,0.72),rgba(226,232,240,0.38))]'"
  >
    <div class="flex flex-none flex-col gap-[16px]">
      <div class="flex flex-wrap items-start justify-between gap-[16px]">
        <div>
          <div class="mb-[6px] flex items-center gap-[8px]">
            <NIcon :size="20"><LogoDocker /></NIcon>
            <h2 class="m-0 text-[20px]">Docker 管理</h2>
          </div>
        </div>

        <NSpace>
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

    </div>

    <NSpin :show="controller.loading" class="docker-body app-scrollbar" :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'">
      <NResult
        v-if="controller.dockerAvailable === false"
        status="warning"
        title="当前环境不可用"
      />

      <NTabs
        v-else
        :value="controller.activeTab"
        :placement="preferLeftTabs ? 'left' : 'top'"
        type="line"
        animated
        class="docker-tabs"
        @update:value="controller.setActiveTab"
      >
        <NTabPane name="overview" tab="概览">
          <DockerOverviewTab :controller="controller" />
        </NTabPane>

        <NTabPane name="containers" tab="容器">
          <DockerContainersTab :controller="controller" />
        </NTabPane>

        <NTabPane name="images" tab="镜像">
          <DockerImagesTab :controller="controller" />
        </NTabPane>

        <NTabPane name="networks" tab="网络">
          <DockerNetworksTab :controller="controller" />
        </NTabPane>

        <NTabPane name="volumes" tab="存储">
          <DockerVolumesTab :controller="controller" />
        </NTabPane>

        <NTabPane name="compose" tab="编排">
          <DockerComposeTab :controller="controller" />
        </NTabPane>
      </NTabs>
    </NSpin>

    <DockerLogsModal :controller="controller" />
    <DockerInspectModal :controller="controller" />
    <DockerRenameContainerModal :controller="controller" />
    <DockerImageTagModal :controller="controller" />
    <DockerImageHistoryModal :controller="controller" />
    <DockerImageRefsModal :controller="controller" />
  </div>
</template>

<style scoped>
.docker-body {
  flex: 1;
  min-height: 0;
}

.docker-body :deep(.n-spin-container),
.docker-body :deep(.n-spin-content) {
  height: 100%;
  min-height: 0;
  overflow: hidden;
}

.docker-body :deep(.n-spin-content) {
  display: block;
}

.docker-tabs {
  height: 100%;
  width: 100%;
  min-width: 0;
}

.docker-tabs :deep(.n-tabs-wrapper),
.docker-tabs :deep(.n-tabs-content-holder),
.docker-tabs :deep(.n-tabs-content) {
  flex: 1;
  height: 100%;
  width: 100%;
  min-width: 0;
  min-height: 0;
}

.docker-tabs :deep(.n-tabs-pane-wrapper),
.docker-tabs :deep(.n-tab-pane) {
  height: 100%;
  width: 100%;
  min-width: 0;
  min-height: 0;
  overflow: auto;
}

@media (min-width: 768px) {
  .docker-tabs :deep(.n-tabs-nav--left) {
    width: 96px;
    flex: 0 0 96px;
  }

  .docker-tabs :deep(.n-tabs-nav-scroll-wrapper) {
    width: 100%;
    flex: 1 1 auto;
    padding-right: 6px;
  }

  .docker-tabs :deep(.n-tabs-nav) {
    width: 100%;
  }

  .docker-tabs :deep(.n-tabs-tab-wrapper) {
    width: 100%;
  }

  .docker-tabs :deep(.n-tabs-tab) {
    width: 100%;
    justify-content: flex-start;
  }

  .docker-tabs :deep(.n-tabs-pane-wrapper) {
    padding-left: 8px;
  }
}
</style>

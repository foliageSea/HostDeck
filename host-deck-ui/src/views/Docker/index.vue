<script setup lang="ts">
import { reactive } from 'vue'
import { useMediaQuery } from '@vueuse/core'
import {
  CubeOutline,
  DiscOutline,
  GitNetworkOutline,
  LayersOutline,
  LogoDocker,
  ServerOutline,
  SettingsOutline,
  SpeedometerOutline,
} from '@vicons/ionicons5'
import { useSettingsStore } from '@/stores/settings'
import DockerContainersTab from './components/DockerContainersTab.vue'
import DockerComposeTab from './components/DockerComposeTab.vue'
import DockerImageHistoryModal from './components/DockerImageHistoryModal.vue'
import DockerImageRefsModal from './components/DockerImageRefsModal.vue'
import DockerImageTagModal from './components/DockerImageTagModal.vue'
import DockerInspectModal from './components/DockerInspectModal.vue'
import DockerImagesTab from './components/DockerImagesTab.vue'
import DockerNetworksTab from './components/DockerNetworksTab.vue'
import DockerOverviewTab from './components/DockerOverviewTab.vue'
import DockerSettingsTab from './components/DockerSettingsTab.vue'
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
    class="docker-page flex h-full min-h-0 flex-col gap-[16px] overflow-hidden p-[18px]"
    :class="settingsStore.isDark ? 'docker-theme-dark' : 'docker-theme-light'"
  >
    <div class="flex flex-none flex-col gap-[16px]">
      <div class="flex flex-wrap items-start justify-between gap-[16px]">
        <div>
          <div class="mb-[6px] flex items-center gap-[8px]">
            <NIcon :size="20"><LogoDocker /></NIcon>
            <h2 class="m-0 text-[20px]">Docker 管理</h2>
          </div>
        </div>
      </div>
    </div>

    <NSpin
      :show="controller.loading"
      class="docker-body app-scrollbar"
      :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'"
    >
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
        <NTabPane name="overview">
          <template #tab>
            <span class="docker-tab-label">
              <NIcon :size="16"><SpeedometerOutline /></NIcon>
              <span>概览</span>
            </span>
          </template>
          <DockerOverviewTab :controller="controller" />
        </NTabPane>

        <NTabPane name="containers">
          <template #tab>
            <span class="docker-tab-label">
              <NIcon :size="16"><CubeOutline /></NIcon>
              <span>容器</span>
            </span>
          </template>
          <DockerContainersTab :controller="controller" />
        </NTabPane>

        <NTabPane name="compose" class="docker-internal-scroll-pane">
          <template #tab>
            <span class="docker-tab-label">
              <NIcon :size="16"><LayersOutline /></NIcon>
              <span>编排</span>
            </span>
          </template>
          <DockerComposeTab :controller="controller" />
        </NTabPane>

        <NTabPane name="images">
          <template #tab>
            <span class="docker-tab-label">
              <NIcon :size="16"><DiscOutline /></NIcon>
              <span>镜像</span>
            </span>
          </template>
          <DockerImagesTab :controller="controller" />
        </NTabPane>

        <NTabPane name="networks" class="docker-internal-scroll-pane">
          <template #tab>
            <span class="docker-tab-label">
              <NIcon :size="16"><GitNetworkOutline /></NIcon>
              <span>网络</span>
            </span>
          </template>
          <DockerNetworksTab :controller="controller" />
        </NTabPane>

        <NTabPane name="volumes" class="docker-internal-scroll-pane">
          <template #tab>
            <span class="docker-tab-label">
              <NIcon :size="16"><ServerOutline /></NIcon>
              <span>存储</span>
            </span>
          </template>
          <DockerVolumesTab :controller="controller" />
        </NTabPane>

        <NTabPane name="settings">
          <template #tab>
            <span class="docker-tab-label">
              <NIcon :size="16"><SettingsOutline /></NIcon>
              <span>设置</span>
            </span>
          </template>
          <DockerSettingsTab
            :connection-id="controller.requireConnectionId()"
            :window-id="props.windowId"
          />
        </NTabPane>
      </NTabs>
    </NSpin>

    <DockerInspectModal :controller="controller" />
    <DockerRenameContainerModal :controller="controller" />
    <DockerImageTagModal :controller="controller" />
    <DockerImageHistoryModal :controller="controller" />
    <DockerImageRefsModal :controller="controller" />
  </div>
</template>

<style scoped>
.docker-theme-dark {
  --docker-tab-card-border: rgba(148, 163, 184, 0.16);
  --docker-card-background: rgba(15, 23, 42, 0.28);
  --docker-text-secondary: rgba(226, 232, 240, 0.78);
  --docker-text-muted: rgba(203, 213, 225, 0.68);
  --docker-text-subtle: rgba(203, 213, 225, 0.56);
}

.docker-theme-light {
  --docker-tab-card-border: rgba(148, 163, 184, 0.22);
  --docker-card-background: rgba(255, 255, 255, 0.28);
  --docker-text-secondary: rgba(71, 85, 105, 0.88);
  --docker-text-muted: rgba(100, 116, 139, 0.78);
  --docker-text-subtle: rgba(100, 116, 139, 0.64);
}

.docker-tab-label {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

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

.docker-tabs :deep(.n-card) {
  border: 1px solid var(--docker-tab-card-border);
  background: transparent;
}

.docker-tabs :deep(.docker-card-field),
.docker-tabs :deep(.compose-project-field),
.docker-tabs :deep(.compose-service-field) {
  border: 1px solid var(--docker-tab-card-border);
  background: transparent;
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
}

.docker-tabs :deep(.n-tabs-pane-wrapper) {
  overflow: hidden;
}

.docker-tabs :deep(.n-tab-pane) {
  overflow: auto;
}

.docker-tabs :deep(.docker-internal-scroll-pane) {
  overflow: hidden;
}

@media (min-width: 768px) {
  .docker-tabs :deep(.n-tabs-nav--left) {
    width: 128px;
    flex: 0 0 128px;
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

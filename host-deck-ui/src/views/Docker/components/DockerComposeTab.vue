<script setup lang="ts">
import { Add } from '@vicons/carbon'
import type { DockerComposeProject } from '@/api/docker'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'
import DockerTabToolbar from './DockerTabToolbar.vue'

const props = defineProps<{ controller: DockerViewController }>()
const settingsStore = useSettingsStore()
const key = (project: DockerComposeProject) => `${project.name}:${project.configFiles}`
const configTitle = (project: DockerComposeProject) =>
  props.controller.getComposeConfigFiles(project).join('\n') || '未返回配置文件'
const running = (project: DockerComposeProject) => project.status.toLowerCase().includes('running')
const stopped = (project: DockerComposeProject) => {
  const status = project.status.toLowerCase()
  return status.includes('exited') || status.includes('stopped')
}
</script>

<template>
  <div
    class="flex h-full min-h-0 flex-col gap-[12px] overflow-hidden"
    :class="settingsStore.isDark ? 'docker-theme-dark' : 'docker-theme-light'"
  >
    <DockerTabToolbar>
      <template #left
        ><NInput
          v-model:value="controller.composeSearchKeyword"
          clearable
          class="w-[min(220px,60vw)] lt-sm:w-full"
          placeholder="搜索编排"
      /></template>
      <template #actions>
        <NButton type="primary" @click="controller.openCreateComposeProject"
          ><template #icon
            ><NIcon><Add /></NIcon></template
          >新建编排</NButton
        >
        <NButton quaternary :loading="controller.loading" @click="controller.refreshCompose"
          >刷新</NButton
        >
      </template>
      <template #meta
        ><NTag round size="small"
          >显示 {{ controller.filteredComposeProjects.length }} /
          {{ controller.composeProjects.length }}</NTag
        ></template
      >
    </DockerTabToolbar>
    <NResult
      v-if="controller.composeAvailable === false"
      status="warning"
      title="Docker Compose 不可用"
    />
    <NEmpty v-else-if="controller.filteredComposeProjects.length === 0" />
    <div v-else class="compose-project-list app-scrollbar app-scrollbar-compact">
      <div
        v-for="project in controller.filteredComposeProjects"
        :key="key(project)"
        class="compose-project-card"
      >
        <div class="mb-[12px] flex flex-wrap items-center justify-between gap-[10px]">
          <div class="min-w-0 flex items-center gap-[10px]">
            <strong class="truncate text-[15px]" :title="project.name">{{ project.name }}</strong
            ><NTag round size="small" :type="controller.getComposeStatusType(project)">{{
              project.status || 'unknown'
            }}</NTag>
          </div>
          <NSpace size="small"
            ><NButton
              v-if="running(project)"
              size="tiny"
              quaternary
              :loading="controller.composeActionLoadingMap[project.name]"
              @click="controller.confirmComposeProjectAction(project, 'stop')"
              >停止</NButton
            ><NButton
              v-else
              size="tiny"
              quaternary
              :loading="controller.composeActionLoadingMap[project.name]"
              @click="controller.confirmComposeProjectAction(project, 'up')"
              >启动</NButton
            ><NButton
              size="tiny"
              quaternary
              :disabled="!running(project)"
              :loading="controller.composeActionLoadingMap[project.name]"
              @click="controller.confirmComposeProjectAction(project, 'restart')"
              >重启</NButton
            ><NButton
              size="tiny"
              quaternary
              type="error"
              :loading="controller.composeActionLoadingMap[project.name]"
              @click="controller.confirmComposeProjectAction(project, 'down')"
              >Down</NButton
            ></NSpace
          >
        </div>
        <div class="compose-project-meta">
          <div class="compose-project-field">
            <span>配置文件</span
            ><strong :title="configTitle(project)">{{ project.configFiles || '-' }}</strong>
          </div>
        </div>
        <div class="mt-[12px] flex justify-end">
          <NButton
            v-if="stopped(project)"
            size="small"
            quaternary
            @click="controller.openEditComposeProject(project)"
            >编辑</NButton
          >
          <NButton size="small" quaternary @click="controller.openComposeServices(project)"
            >详情</NButton
          >
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.docker-theme-dark {
  --compose-card-border: rgba(148, 163, 184, 0.16);
  --compose-field-bg: rgba(15, 23, 42, 0.38);
  --compose-label-color: rgba(226, 232, 240, 0.52);
  --compose-value-color: rgba(248, 250, 252, 0.9);
}
.docker-theme-light {
  --compose-card-border: rgba(148, 163, 184, 0.22);
  --compose-field-bg: rgba(241, 245, 249, 0.92);
  --compose-label-color: rgba(100, 116, 139, 0.9);
  --compose-value-color: rgba(30, 41, 59, 0.92);
}
.compose-project-list {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding-right: 4px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.compose-project-card {
  border: 1px solid var(--compose-card-border);
  border-radius: var(--app-radius-card);
  padding: 10px;
}
.compose-project-meta {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 7px;
}
.compose-project-field {
  min-width: 0;
  border-radius: var(--app-radius-item);
  background: var(--compose-field-bg);
  padding: 6px 8px;
}
.compose-project-field span {
  display: block;
  margin-bottom: 2px;
  color: var(--compose-label-color);
  font-size: 11px;
}
.compose-project-field strong {
  display: block;
  overflow: hidden;
  color: var(--compose-value-color);
  font-size: 12px;
  font-weight: 500;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>

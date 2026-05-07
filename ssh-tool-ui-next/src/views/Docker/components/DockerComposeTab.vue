<script setup lang="ts">
import { ChevronDown } from '@vicons/carbon'
import type { DockerComposeProject } from '@/api/docker'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'

const props = defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()

function getProjectKey(project: DockerComposeProject) {
  return `${project.name}:${project.configFiles}`
}

function getConfigTitle(project: DockerComposeProject) {
  const files = props.controller.getComposeConfigFiles(project)
  return files.length ? files.join('\n') : '未返回配置文件'
}

function formatComposePorts(ports: string) {
  const rawPorts = ports.trim()
  if (!rawPorts) {
    return '-'
  }

  const publishers = rawPorts.match(/\{[^}]+\}/g)
  if (!publishers) {
    return rawPorts
  }

  const formattedPorts = publishers
    .map((publisher) => {
      const targetPort = publisher.match(/TargetPort:\s*([^,}]+)/)?.[1]?.trim()
      const publishedPort = publisher.match(/PublishedPort:\s*([^,}]+)/)?.[1]?.trim()
      const protocol = publisher.match(/Protocol:\s*([^,}]+)/)?.[1]?.trim()

      if (!targetPort) {
        return ''
      }

      const protocolSuffix = protocol ? `/${protocol}` : ''
      return publishedPort ? `${publishedPort}:${targetPort}${protocolSuffix}` : `${targetPort}${protocolSuffix}`
    })
    .filter(Boolean)

  return formattedPorts.length ? Array.from(new Set(formattedPorts)).join(', ') : rawPorts
}
</script>

<template>
  <div class="flex flex-col gap-[12px]" :class="settingsStore.isDark ? 'docker-theme-dark' : 'docker-theme-light'">
    <div class="flex flex-wrap items-center justify-end gap-[12px]">
      <NSpace>
        <NButton type="primary" @click="controller.openCreateComposeProject">新建编排</NButton>
        <NButton quaternary :loading="controller.loading" @click="controller.refreshCompose">刷新编排</NButton>
      </NSpace>
    </div>

    <NResult
      v-if="controller.composeAvailable === false"
      status="warning"
      title="Docker Compose 不可用"
    />

    <NEmpty v-else-if="controller.composeProjects.length === 0">
    </NEmpty>

    <NCollapse v-else accordion :default-expanded-names="controller.selectedComposeProjectName">
      <NCollapseItem v-for="project in controller.composeProjects" :key="getProjectKey(project)" :name="project.name">
        <template #header>
          <div class="min-w-0 flex flex-1 items-center gap-[10px]">
            <strong class="truncate text-[15px]" :title="project.name">{{ project.name }}</strong>
            <NTag round size="small" :type="controller.getComposeStatusType(project)">{{ project.status || 'unknown' }}</NTag>
          </div>
        </template>

        <template #arrow>
          <NIcon><ChevronDown /></NIcon>
        </template>

        <template #header-extra>
          <NSpace size="small" @click.stop>
            <NButton size="tiny" quaternary :loading="controller.composeActionLoadingMap[project.name]" @click="controller.confirmComposeProjectAction(project, 'up')">启动</NButton>
            <NButton size="tiny" quaternary :loading="controller.composeActionLoadingMap[project.name]" @click="controller.confirmComposeProjectAction(project, 'stop')">停止</NButton>
            <NButton size="tiny" quaternary :loading="controller.composeActionLoadingMap[project.name]" @click="controller.confirmComposeProjectAction(project, 'restart')">重启</NButton>
            <NButton size="tiny" quaternary @click="controller.viewComposeLogs(project)">日志</NButton>
            <NButton size="tiny" quaternary type="error" :loading="controller.composeActionLoadingMap[project.name]" @click="controller.confirmComposeProjectAction(project, 'down')">Down</NButton>
          </NSpace>
        </template>

        <div class="compose-project-card">
          <div class="compose-project-meta">
            <div class="compose-project-field">
              <span>工作目录</span>
              <strong :title="project.workingDir || '-'">{{ project.workingDir || '-' }}</strong>
            </div>
            <div class="compose-project-field">
              <span>配置文件</span>
              <strong :title="getConfigTitle(project)">{{ project.configFiles || '-' }}</strong>
            </div>
          </div>

          <div class="mt-[12px] flex flex-wrap items-center justify-end gap-[8px]">
            <NButton size="small" quaternary :loading="controller.composeServiceLoadingMap[project.name]" @click="controller.refreshComposeServices(project)">加载服务</NButton>
          </div>

          <div v-if="controller.composeServicesMap[project.name]?.length" class="compose-service-grid">
            <NCard v-for="service in controller.composeServicesMap[project.name]" :key="service.id || service.name" size="small" :bordered="false" class="compose-service-card">
              <template #header>
                <div class="min-w-0">
                  <div class="truncate text-[14px] font-600" :title="service.service || service.name">{{ service.service || service.name }}</div>
                  <div class="mt-[3px] truncate text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.52)]' : 'text-[rgba(100,116,139,0.82)]'" :title="service.name">
                    {{ service.name || '-' }}
                  </div>
                </div>
              </template>

              <template #header-extra>
                <NTag round size="small" :type="controller.getComposeServiceStatusType(service)">{{ service.state || service.status || 'unknown' }}</NTag>
              </template>

              <div class="compose-service-fields">
                <div class="compose-service-field wide">
                  <span>镜像</span>
                  <strong :title="service.image || '-'">{{ service.image || '-' }}</strong>
                </div>
                <div class="compose-service-field wide">
                  <span>端口</span>
                  <strong :title="service.ports || '-'">{{ formatComposePorts(service.ports) }}</strong>
                </div>
                <div class="compose-service-field wide">
                  <span>状态</span>
                  <strong :title="service.status || '-'">{{ service.status || '-' }}</strong>
                </div>
              </div>
            </NCard>
          </div>
        </div>
      </NCollapseItem>
    </NCollapse>
  </div>
</template>

<style scoped>
.docker-theme-dark {
  --compose-card-border: rgba(148, 163, 184, 0.16);
  --compose-card-bg: linear-gradient(145deg, rgba(15, 23, 42, 0.72), rgba(30, 41, 59, 0.46));
  --compose-field-bg: rgba(15, 23, 42, 0.38);
  --compose-label-color: rgba(226, 232, 240, 0.52);
  --compose-value-color: rgba(248, 250, 252, 0.9);
}

.docker-theme-light {
  --compose-card-border: rgba(148, 163, 184, 0.22);
  --compose-card-bg: linear-gradient(145deg, rgba(255, 255, 255, 0.96), rgba(241, 245, 249, 0.92));
  --compose-field-bg: rgba(241, 245, 249, 0.92);
  --compose-label-color: rgba(100, 116, 139, 0.9);
  --compose-value-color: rgba(30, 41, 59, 0.92);
}

.compose-project-card {
  border: 1px solid var(--compose-card-border);
  border-radius: 16px;
  background: var(--compose-card-bg);
  padding: 12px;
}

.compose-project-meta,
.compose-service-fields {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
}

.compose-project-field,
.compose-service-field {
  min-width: 0;
  border-radius: 12px;
  background: var(--compose-field-bg);
  padding: 9px 10px;
}

.compose-service-field.wide {
  grid-column: 1 / -1;
}

.compose-project-field span,
.compose-service-field span {
  display: block;
  margin-bottom: 4px;
  color: var(--compose-label-color);
  font-size: 12px;
}

.compose-project-field strong,
.compose-service-field strong {
  display: block;
  overflow: hidden;
  color: var(--compose-value-color);
  font-size: 13px;
  font-weight: 500;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.compose-service-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, 320px);
  gap: 12px;
  margin-top: 12px;
}

.compose-service-card {
  width: 320px;
  border: 1px solid var(--compose-card-border);
  background: var(--compose-card-bg);
}

@media (max-width: 640px) {
  .compose-project-meta,
  .compose-service-fields,
  .compose-service-grid {
    grid-template-columns: 1fr;
  }

  .compose-service-card {
    width: 100%;
  }
}
</style>

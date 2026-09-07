<script setup lang="ts">
import { Add } from '@vicons/carbon'
import { Ellipsis, Layers3, RefreshCw, Search } from '@lucide/vue'
import type { DockerComposeProject } from '@/api/docker'
import type { DockerViewController } from '../hooks/useDockerView'
import { getComposeStatusPresentation } from '../hooks/dockerViewHelpers'
import DockerTabToolbar from './DockerTabToolbar.vue'

const props = defineProps<{ controller: DockerViewController }>()
const key = (project: DockerComposeProject) => `${project.name}:${project.configFiles}`
const configTitle = (project: DockerComposeProject) =>
  props.controller.getComposeConfigFiles(project).join('\n') || '未返回配置文件'
const running = (project: DockerComposeProject) => project.status.toLowerCase().includes('running')
const stopped = (project: DockerComposeProject) => {
  const status = project.status.toLowerCase()
  return status.includes('exited') || status.includes('stopped')
}

function getComposeCounts(project: DockerComposeProject) {
  const matches = Array.from(
    project.status.matchAll(/(?:running|exited|stopped)\s*\(?\s*(\d+)\s*\)?/gi),
  )
  const runningMatch = project.status.match(/running\s*\(?\s*(\d+)\s*\)?/i)
  const total = matches.reduce((sum, match) => sum + Number(match[1] ?? 0), 0)
  const runningCount = Number(runningMatch?.[1] ?? (running(project) ? 1 : 0))

  return { running: runningCount, total: total || (project.status ? 1 : 0) }
}

const getComposeMoreActionOptions = (project: DockerComposeProject) => [
  { key: 'down', label: '下线' },
  { key: 'edit', label: '编辑', disabled: !stopped(project) },
  { key: 'directory', label: '打开目录' },
  { key: 'details', label: '详情' },
]

function handleComposeMoreAction(project: DockerComposeProject, action: string) {
  switch (action) {
    case 'down':
      props.controller.confirmComposeProjectAction(project, 'down')
      break
    case 'edit':
      props.controller.openEditComposeProject(project)
      break
    case 'directory':
      props.controller.openComposeConfigDirectory(project)
      break
    case 'details':
      props.controller.openComposeServices(project)
      break
  }
}
</script>

<template>
  <div class="flex h-full min-h-0 flex-col overflow-hidden">
    <DockerTabToolbar>
      <template #left>
        <NButton type="primary" @click="controller.openCreateComposeProject"
          ><template #icon
            ><NIcon><Add /></NIcon></template
          >新建编排</NButton
        >
      </template>

      <template #actions>
        <NInput
          v-model:value="controller.composeSearchKeyword"
          clearable
          class="compose-search-input"
          placeholder="搜索编排"
        >
          <template #prefix><Search :size="16" /></template>
        </NInput>
        <NTooltip>
          <template #trigger>
            <NButton
              circle
              :loading="controller.loading"
              aria-label="刷新编排"
              @click="controller.refreshCompose"
            >
              <RefreshCw :size="16" />
            </NButton>
          </template>
          刷新
        </NTooltip>
      </template>
    </DockerTabToolbar>
    <NResult
      v-if="controller.composeAvailable === false"
      status="warning"
      title="Docker Compose 不可用"
    />
    <NEmpty v-else-if="controller.filteredComposeProjects.length === 0" class="my-auto" />
    <div v-else class="compose-list app-scrollbar app-scrollbar-compact">
      <div class="compose-list__summary">
        共 {{ controller.filteredComposeProjects.length }} 个编排项目
      </div>
      <article
        v-for="project in controller.filteredComposeProjects"
        :key="key(project)"
        class="compose-card"
      >
        <div class="compose-card__icon" aria-hidden="true">
          <Layers3 :size="30" :stroke-width="1.8" />
        </div>

        <div class="compose-card__content">
          <div class="compose-card__heading">
            <strong :title="project.name">{{ project.name }}</strong>
            <NTooltip trigger="hover" placement="top-start">
              <template #trigger>
                <NTag size="small" :type="getComposeStatusPresentation(project).type">
                  {{ getComposeStatusPresentation(project).label }}
                </NTag>
              </template>
              <div class="grid max-w-[360px] gap-[5px]">
                <strong>{{ getComposeStatusPresentation(project).description }}</strong>
                <span class="break-anywhere opacity-72">详细状态：{{ project.status || '-' }}</span>
              </div>
            </NTooltip>
          </div>

          <div class="compose-card__metadata">
            <span :title="configTitle(project)"
              ><small>配置</small>{{ project.configFiles || '-' }}</span
            >
          </div>
        </div>

        <div class="compose-card__count">
          <strong>
            <span>{{ getComposeCounts(project).running }}</span> /
            {{ getComposeCounts(project).total }}
          </strong>
          <small>运行中服务 / 总数</small>
        </div>

        <div class="compose-card__actions">
          <NButton
            v-if="running(project)"
            text
            type="primary"
            :loading="controller.composeActionLoadingMap[project.name]"
            @click="controller.confirmComposeProjectAction(project, 'stop')"
          >
            停止
          </NButton>
          <NButton
            v-else
            text
            type="primary"
            :loading="controller.composeActionLoadingMap[project.name]"
            @click="controller.confirmComposeProjectAction(project, 'up')"
          >
            启动
          </NButton>
          <NButton
            text
            type="primary"
            :disabled="!running(project)"
            :loading="controller.composeActionLoadingMap[project.name]"
            @click="controller.confirmComposeProjectAction(project, 'restart')"
          >
            重启
          </NButton>
          <NDropdown
            trigger="click"
            :options="getComposeMoreActionOptions(project)"
            @select="(action: string | number) => handleComposeMoreAction(project, String(action))"
          >
            <NButton quaternary circle aria-label="更多编排操作">
              <Ellipsis :size="19" />
            </NButton>
          </NDropdown>
        </div>
      </article>
    </div>
  </div>
</template>

<style scoped>
.compose-search-input {
  width: min(320px, 36vw) !important;
  min-width: 200px;
}

.compose-list {
  display: flex;
  min-height: 0;
  flex: 1;
  flex-direction: column;
  gap: 12px;
  overflow: auto;
  padding: 1px 6px 8px 1px;
}

.compose-list__summary {
  flex: none;
  padding: 0 4px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
  font-size: 12px;
}

.compose-card {
  display: grid;
  min-width: 0;
  grid-template-columns: 64px minmax(0, 1fr) minmax(130px, 0.35fr) auto;
  align-items: center;
  gap: 22px;
  border: 1px solid var(--docker-tab-card-border, rgba(148, 163, 184, 0.2));
  border-radius: 12px;
  background: var(--docker-card-background, transparent);
  padding: 24px 26px;
  transition:
    border-color 0.2s ease,
    box-shadow 0.2s ease,
    transform 0.2s ease;
}

.compose-card:hover {
  border-color: var(--app-primary-border);
  box-shadow: 0 8px 24px -20px rgba(var(--app-primary-rgb), 0.7);
  transform: translateY(-1px);
}

.compose-card__icon {
  display: grid;
  width: 64px;
  height: 64px;
  place-items: center;
  border-radius: 12px;
  background: var(--app-primary-soft);
  color: var(--app-primary-color);
}

.compose-card__content {
  min-width: 0;
}

.compose-card__heading {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 10px;
}

.compose-card__heading > strong {
  overflow: hidden;
  font-size: 18px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.compose-card__metadata {
  display: flex;
  min-width: 0;
  margin-top: 12px;
  color: var(--docker-text-secondary, rgba(71, 85, 105, 0.88));
}

.compose-card__metadata > span {
  min-width: 0;
  max-width: 54%;
  overflow: hidden;
  border-left: 1px solid var(--docker-tab-card-border, rgba(148, 163, 184, 0.2));
  padding: 0 16px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.compose-card__metadata > span:first-child {
  border-left: 0;
  padding-left: 0;
}

.compose-card__metadata small {
  margin-right: 6px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
}

.compose-card__count {
  display: grid;
  justify-items: center;
  gap: 4px;
  white-space: nowrap;
}

.compose-card__count strong {
  font-size: 17px;
  font-weight: 500;
}

.compose-card__count strong span {
  color: #18a058;
}

.compose-card__count small {
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
}

.compose-card__actions {
  display: flex;
  flex: none;
  align-items: center;
  gap: 16px;
}

@media (max-width: 1000px) {
  .compose-card {
    grid-template-columns: 56px minmax(0, 1fr) auto;
    gap: 16px;
  }

  .compose-card__icon {
    width: 56px;
    height: 56px;
  }

  .compose-card__count {
    grid-column: 2;
    justify-items: start;
  }

  .compose-card__count small {
    display: none;
  }

  .compose-card__actions {
    grid-column: 3;
    grid-row: 1 / span 2;
  }
}

@media (max-width: 640px) {
  .compose-search-input {
    width: calc(100% - 42px) !important;
    min-width: 0;
  }

  .compose-card {
    grid-template-columns: 48px minmax(0, 1fr);
    gap: 10px;
    padding: 16px 14px;
  }

  .compose-card__icon {
    width: 48px;
    height: 48px;
  }

  .compose-card__metadata {
    display: grid;
    gap: 6px;
  }

  .compose-card__metadata > span {
    max-width: 100%;
    border-left: 0;
    padding: 0;
  }

  .compose-card__count {
    grid-column: 2;
  }

  .compose-card__actions {
    grid-column: 2;
    grid-row: auto;
    justify-content: flex-end;
    gap: 14px;
  }
}
</style>

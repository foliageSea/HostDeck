<script setup lang="ts">
import { Add } from '@vicons/carbon'
import type { DockerComposeProject } from '@/api/docker'
import type { DockerViewController } from '../hooks/useDockerView'
import { getComposeStatusPresentation } from '../hooks/dockerViewHelpers'
import DockerResourceTable from './DockerResourceTable.vue'
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
  <div class="flex h-full min-h-0 flex-col gap-[12px] overflow-hidden">
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
    </DockerTabToolbar>
    <NResult
      v-if="controller.composeAvailable === false"
      status="warning"
      title="Docker Compose 不可用"
    />
    <NEmpty v-else-if="controller.filteredComposeProjects.length === 0" />
    <DockerResourceTable v-else min-width="860px">
      <thead>
        <tr>
          <th style="width: 18%">项目</th>
          <th style="width: 14%">状态</th>
          <th>配置文件</th>
          <th class="docker-table-actions-column" style="width: 190px; text-align: right">操作</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="project in controller.filteredComposeProjects" :key="key(project)">
          <td>
            <span class="docker-table-primary" :title="project.name">{{ project.name }}</span>
          </td>
          <td>
            <NTooltip trigger="hover" placement="top-start">
              <template #trigger>
                <div class="docker-table-status">
                  <NTag round size="small" :type="getComposeStatusPresentation(project).type">
                    {{ getComposeStatusPresentation(project).label }}
                  </NTag>
                </div>
              </template>
              <div class="grid max-w-[360px] gap-[5px]">
                <strong>{{ getComposeStatusPresentation(project).description }}</strong>
                <span class="break-anywhere opacity-72">详细状态：{{ project.status || '-' }}</span>
              </div>
            </NTooltip>
          </td>
          <td>
            <span class="docker-table-primary" :title="configTitle(project)">{{
              project.configFiles || '-'
            }}</span>
          </td>
          <td class="docker-table-actions-column">
            <div class="docker-table-actions">
              <NButton
                v-if="running(project)"
                size="tiny"
                quaternary
                :loading="controller.composeActionLoadingMap[project.name]"
                @click="controller.confirmComposeProjectAction(project, 'stop')"
                >停止</NButton
              >
              <NButton
                v-else
                size="tiny"
                quaternary
                :loading="controller.composeActionLoadingMap[project.name]"
                @click="controller.confirmComposeProjectAction(project, 'up')"
                >启动</NButton
              >
              <NButton
                size="tiny"
                quaternary
                :disabled="!running(project)"
                :loading="controller.composeActionLoadingMap[project.name]"
                @click="controller.confirmComposeProjectAction(project, 'restart')"
                >重启</NButton
              >
              <NDropdown
                trigger="click"
                :options="getComposeMoreActionOptions(project)"
                @select="
                  (action: string | number) => handleComposeMoreAction(project, String(action))
                "
              >
                <NButton size="tiny" quaternary>更多</NButton>
              </NDropdown>
            </div>
          </td>
        </tr>
      </tbody>
    </DockerResourceTable>
  </div>
</template>

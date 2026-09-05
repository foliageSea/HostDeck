<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { LogoDocker } from '@vicons/ionicons5'
import { dockerApi, type DockerComposeProject, type DockerComposeService } from '@/api/docker'
import { getUiApi } from '@/lib/ui'
import { useSshStore } from '@/stores/ssh'
import {
  getComposeConfigFiles,
  getComposeProjectPayload,
  getComposeServiceStatusPresentation,
} from '../hooks/dockerViewHelpers'
import DockerResourceTable from './DockerResourceTable.vue'
const props = defineProps<{
  windowId?: string
  connectionId?: string
  project: DockerComposeProject
}>()
const sshStore = useSshStore()
const loading = ref(false)
const services = ref<DockerComposeService[]>([])

function formatPorts(value: string) {
  const raw = value.trim()
  if (!raw) return '-'

  const publishers = raw.match(/\{[^}]+\}/g)
  if (!publishers) return raw

  const ports = publishers
    .map((publisher) => {
      const target = publisher.match(/TargetPort:\s*([^,}]+)/)?.[1]?.trim()
      const published = publisher.match(/PublishedPort:\s*([^,}]+)/)?.[1]?.trim()
      const protocol = publisher.match(/Protocol:\s*([^,}]+)/)?.[1]?.trim()
      if (!target) return ''

      return `${published ? `${published}:` : ''}${target}${protocol ? `/${protocol}` : ''}`
    })
    .filter(Boolean)

  return ports.length ? Array.from(new Set(ports)).join(', ') : raw
}
async function load() {
  const payload = getComposeProjectPayload(props.project)
  const connectionId = props.connectionId ?? sshStore.connectionId
  if (!payload || !connectionId)
    return getUiApi().message.error('该编排项目缺少连接或配置文件路径。')
  loading.value = true
  try {
    services.value = await dockerApi.listComposeServices(connectionId, payload)
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '加载编排服务失败。')
  } finally {
    loading.value = false
  }
}
onMounted(() => void load())
</script>
<template>
  <div class="flex h-full min-h-0 flex-col overflow-hidden">
    <div
      class="flex shrink-0 flex-wrap items-center justify-between gap-[12px] border-b px-[18px] py-[14px]"
    >
      <div class="min-w-0">
        <div class="flex items-center gap-[8px]">
          <NIcon :size="20"><LogoDocker /></NIcon>
          <h2 class="m-0 truncate text-[18px]">编排服务 · {{ project.name }}</h2>
        </div>
        <span class="text-[12px]" :title="getComposeConfigFiles(project).join('\n')"
          >配置文件：{{ project.configFiles || '-' }}</span
        >
      </div>
      <NSpace><NButton quaternary :loading="loading" @click="load">刷新</NButton></NSpace>
    </div>
    <NSpin :show="loading" class="compose-services-body">
      <div class="flex h-full min-h-0 flex-col p-[18px]">
        <NEmpty v-if="services.length === 0 && !loading" description="未加载到编排服务" />
        <DockerResourceTable v-else min-width="980px">
          <thead>
            <tr>
              <th style="width: 220px">服务</th>
              <th style="width: 140px">状态</th>
              <th style="width: 260px">镜像</th>
              <th style="width: 220px">端口</th>
              <th>详细状态</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="service in services" :key="service.id || service.name">
              <td>
                <span class="docker-table-primary" :title="service.service || service.name">
                  {{ service.service || service.name || '-' }}
                </span>
                <span class="docker-table-secondary" :title="service.name || service.id">
                  {{ service.name || service.id || '-' }}
                </span>
              </td>
              <td>
                <NTooltip trigger="hover" placement="top-start">
                  <template #trigger>
                    <div class="docker-table-status">
                      <NTag
                        round
                        size="small"
                        :type="getComposeServiceStatusPresentation(service).type"
                      >
                        {{ getComposeServiceStatusPresentation(service).label }}
                      </NTag>
                    </div>
                  </template>
                  <div class="grid max-w-[360px] gap-[5px]">
                    <strong>{{ getComposeServiceStatusPresentation(service).description }}</strong>
                    <span class="break-anywhere opacity-72">
                      详细状态：{{ service.status || '-' }}
                    </span>
                    <span class="break-anywhere opacity-72">
                      引擎状态：{{ service.state || '-' }}
                    </span>
                  </div>
                </NTooltip>
              </td>
              <td>
                <span class="docker-table-primary" :title="service.image || '-'">
                  {{ service.image || '-' }}
                </span>
              </td>
              <td>
                <span class="docker-table-primary" :title="formatPorts(service.ports)">
                  {{ formatPorts(service.ports) }}
                </span>
              </td>
              <td>
                <span class="docker-table-primary" :title="service.status || '-'">
                  {{ service.status || service.state || '-' }}
                </span>
              </td>
            </tr>
          </tbody>
        </DockerResourceTable>
      </div>
    </NSpin>
  </div>
</template>

<style scoped>
.compose-services-body {
  flex: 1;
  min-height: 0;
}

.compose-services-body :deep(.n-spin-container),
.compose-services-body :deep(.n-spin-content) {
  height: 100%;
  min-height: 0;
}
</style>

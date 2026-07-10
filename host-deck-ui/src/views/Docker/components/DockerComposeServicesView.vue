<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { LogoDocker } from '@vicons/ionicons5'
import {
  dockerApi,
  type DockerComposeProject,
  type DockerComposeProjectPayload,
  type DockerComposeService,
} from '@/api/docker'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import {
  getComposeConfigFiles,
  getComposeProjectPayload,
  getComposeServiceStatusType,
} from '../hooks/dockerViewHelpers'

const props = defineProps<{
  windowId?: string
  connectionId?: string
  host?: string
  project: DockerComposeProject
}>()

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const loading = ref(false)
const services = ref<DockerComposeService[]>([])

function requireConnectionId() {
  const connectionId = props.connectionId ?? sshStore.connectionId
  if (!connectionId) {
    throw new Error('当前没有可用的 Docker 连接。')
  }

  return connectionId
}

function requireProjectPayload(): DockerComposeProjectPayload {
  const payload = getComposeProjectPayload(props.project)
  if (!payload) {
    throw new Error('该编排项目缺少 compose 配置文件路径，无法加载服务。')
  }

  return payload
}

function closeWindow() {
  if (props.windowId) {
    desktopStore.closeWindow(props.windowId)
  }
}

function getConfigTitle(project: DockerComposeProject) {
  const files = getComposeConfigFiles(project)
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
      return publishedPort
        ? `${publishedPort}:${targetPort}${protocolSuffix}`
        : `${targetPort}${protocolSuffix}`
    })
    .filter(Boolean)

  return formattedPorts.length ? Array.from(new Set(formattedPorts)).join(', ') : rawPorts
}

async function loadServices() {
  loading.value = true
  try {
    const connectionId = requireConnectionId()
    services.value = await dockerApi.listComposeServices(connectionId, requireProjectPayload())
  } catch (error) {
    console.error('Failed to load compose services', error)
    getUiApi().message.error(error instanceof Error ? error.message : '加载编排服务失败。')
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  void loadServices()
})
</script>

<template>
  <div
    class="flex h-full min-h-0 flex-col overflow-hidden"
    :class="
      settingsStore.isDark
        ? 'docker-theme-dark bg-[linear-gradient(180deg,rgba(15,23,42,0.18),rgba(15,23,42,0.06))]'
        : 'docker-theme-light bg-[linear-gradient(180deg,rgba(255,255,255,0.7),rgba(226,232,240,0.36))]'
    "
  >
    <div
      class="flex shrink-0 flex-wrap items-center justify-between gap-[12px] border-b px-[18px] py-[14px]"
      :class="
        settingsStore.isDark
          ? 'border-[rgba(148,163,184,0.14)] text-[#e2e8f0]'
          : 'border-[rgba(148,163,184,0.22)] text-[#1e293b]'
      "
    >
      <div class="min-w-0">
        <div class="mb-[4px] flex items-center gap-[8px]">
          <NIcon :size="20"><LogoDocker /></NIcon>
          <h2 class="m-0 truncate text-[18px]">编排服务 · {{ project.name }}</h2>
        </div>
        <div
          class="flex flex-wrap gap-[8px] text-[12px]"
          :class="
            settingsStore.isDark ? 'text-[rgba(226,232,240,0.58)]' : 'text-[rgba(71,85,105,0.78)]'
          "
        >
          <span :title="project.workingDir || '-'">工作目录：{{ project.workingDir || '-' }}</span>
          <span :title="getConfigTitle(project)">配置文件：{{ project.configFiles || '-' }}</span>
        </div>
      </div>

      <NSpace>
        <NButton quaternary :loading="loading" @click="loadServices">刷新</NButton>
        <NButton quaternary @click="closeWindow">关闭</NButton>
      </NSpace>
    </div>

    <NSpin
      :show="loading"
      class="compose-services-body app-scrollbar"
      :class="settingsStore.isDark ? 'app-scrollbar-dark' : 'app-scrollbar-light'"
    >
      <NEmpty v-if="services.length === 0 && !loading" description="未加载到编排服务" />

      <div v-else class="compose-service-grid">
        <NCard
          v-for="service in services"
          :key="service.id || service.name"
          size="small"
          :bordered="false"
          class="compose-service-card"
        >
          <template #header>
            <div class="min-w-0">
              <div class="truncate text-[14px] font-600" :title="service.service || service.name">
                {{ service.service || service.name }}
              </div>
              <div
                class="mt-[3px] truncate text-[12px]"
                :class="
                  settingsStore.isDark
                    ? 'text-[rgba(226,232,240,0.52)]'
                    : 'text-[rgba(100,116,139,0.82)]'
                "
                :title="service.name"
              >
                {{ service.name || '-' }}
              </div>
            </div>
          </template>

          <template #header-extra>
            <NTag round size="small" :type="getComposeServiceStatusType(service)">{{
              service.state || service.status || 'unknown'
            }}</NTag>
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
    </NSpin>
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

.compose-services-body {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 18px;
}

.compose-services-body :deep(.n-spin-container),
.compose-services-body :deep(.n-spin-content) {
  min-height: 100%;
}

.compose-service-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 10px;
}

.compose-service-card {
  width: 100%;
  --n-color: transparent;
  border: 1px solid var(--compose-card-border);
  background: transparent;
}

.compose-service-card :deep(.n-card-header) {
  padding: 10px 12px 8px;
}

.compose-service-card :deep(.n-card__content) {
  padding: 0 12px 10px;
}

.compose-service-fields {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 7px;
}

.compose-service-field {
  min-width: 0;
  border-radius: var(--app-radius-item);
  background: var(--compose-field-bg);
  padding: 6px 8px;
}

.compose-service-field.wide {
  grid-column: auto;
}

.compose-service-field span {
  display: block;
  margin-bottom: 2px;
  color: var(--compose-label-color);
  font-size: 11px;
}

.compose-service-field strong {
  display: block;
  overflow: hidden;
  color: var(--compose-value-color);
  font-size: 12px;
  font-weight: 500;
  text-overflow: ellipsis;
  white-space: nowrap;
}

@media (max-width: 640px) {
  .compose-service-fields,
  .compose-service-grid {
    grid-template-columns: 1fr;
  }
}
</style>

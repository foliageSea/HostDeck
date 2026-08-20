<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { LogoDocker } from '@vicons/ionicons5'
import { dockerApi, type DockerComposeProject, type DockerComposeService } from '@/api/docker'
import { getUiApi } from '@/lib/ui'
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
  project: DockerComposeProject
}>()
const settingsStore = useSettingsStore()
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
  <div
    class="flex h-full min-h-0 flex-col overflow-hidden"
    :class="settingsStore.isDark ? 'docker-theme-dark' : 'docker-theme-light'"
  >
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
    <NSpin :show="loading" class="min-h-0 flex-1 overflow-auto p-[18px] app-scrollbar"
      ><NEmpty v-if="services.length === 0 && !loading" description="未加载到编排服务" />
      <div v-else class="compose-service-grid">
        <NCard
          v-for="service in services"
          :key="service.id || service.name"
          size="small"
          :bordered="false"
          class="compose-service-card"
          ><template #header>{{ service.service || service.name }}</template
          ><template #header-extra
            ><NTag round size="small" :type="getComposeServiceStatusType(service)">{{
              service.state || service.status || 'unknown'
            }}</NTag></template
          >
          <div class="compose-service-fields">
            <div class="compose-service-field">
              <span>镜像</span
              ><strong :title="service.image || '-'">{{ service.image || '-' }}</strong>
            </div>
            <div class="compose-service-field">
              <span>端口</span
              ><strong :title="formatPorts(service.ports)">{{ formatPorts(service.ports) }}</strong>
            </div>
            <div class="compose-service-field">
              <span>状态</span
              ><strong :title="service.status || '-'">{{ service.status || '-' }}</strong>
            </div>
          </div></NCard
        >
      </div></NSpin
    >
  </div>
</template>

<style scoped>
.docker-theme-dark {
  --compose-card-border: rgba(148, 163, 184, 0.16);
  --compose-field-bg: rgba(15, 23, 42, 0.5);
  --compose-label-color: rgba(226, 232, 240, 0.52);
  --compose-value-color: rgba(248, 250, 252, 0.92);
}

.docker-theme-light {
  --compose-card-border: rgba(148, 163, 184, 0.22);
  --compose-field-bg: rgba(241, 245, 249, 0.94);
  --compose-label-color: rgba(100, 116, 139, 0.9);
  --compose-value-color: rgba(30, 41, 59, 0.94);
}

.compose-service-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 10px;
}

.compose-service-card {
  width: 100%;
  border: 1px solid var(--compose-card-border);
  background: transparent;
}

.compose-service-card :deep(.n-card-header) {
  padding: 11px 12px 9px;
}

.compose-service-card :deep(.n-card__content) {
  padding: 0 12px 12px;
}

.compose-service-fields {
  display: grid;
  grid-template-columns: minmax(0, 1.2fr) minmax(0, 1fr) minmax(0, 1fr);
  gap: 7px;
}

.compose-service-field {
  min-width: 0;
  border-radius: var(--app-radius-item);
  background: var(--compose-field-bg);
  padding: 7px 9px;
}

.compose-service-field span {
  display: block;
  margin-bottom: 3px;
  color: var(--compose-label-color);
  font-size: 11px;
}

.compose-service-field strong {
  display: block;
  overflow: hidden;
  color: var(--compose-value-color);
  font-family: var(--app-font-mono, ui-monospace, SFMono-Regular, Menlo, monospace);
  font-size: 12px;
  font-weight: 500;
  line-height: 1.45;
  text-overflow: ellipsis;
  white-space: nowrap;
}

@media (max-width: 640px) {
  .compose-service-fields {
    grid-template-columns: 1fr;
  }
}
</style>

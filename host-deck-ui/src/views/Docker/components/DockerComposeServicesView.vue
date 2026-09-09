<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Box, Layers3, RefreshCw, Search } from '@lucide/vue'
import { dockerApi, type DockerComposeProject, type DockerComposeService } from '@/api/docker'
import CopyableText from '@/components/common/CopyableText.vue'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'
import {
  getComposeConfigFiles,
  getComposeProjectPayload,
  getComposeServiceStatusPresentation,
} from '../hooks/dockerViewHelpers'

const props = defineProps<{
  windowId?: string
  connectionId?: string
  project: DockerComposeProject
}>()
const sshStore = useSshStore()
const settingsStore = useSettingsStore()
const loading = ref(false)
const services = ref<DockerComposeService[]>([])
const searchKeyword = ref('')
const filteredServices = computed(() => {
  const keyword = searchKeyword.value.trim().toLowerCase()
  if (!keyword) return services.value

  return services.value.filter((service) =>
    [service.service, service.name, service.image, service.state, service.status, service.ports].some(
      (value) => value.toLowerCase().includes(keyword),
    ),
  )
})

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
    class="compose-services-page flex h-full min-h-0 flex-col overflow-hidden"
    :class="settingsStore.isDark ? 'compose-services-theme-dark' : 'compose-services-theme-light'"
  >
    <header
      class="compose-services-header flex shrink-0 flex-wrap items-center justify-between gap-[12px] px-[18px] py-[14px]"
    >
      <div class="min-w-0">
        <div class="flex items-center gap-[8px]">
          <Layers3 :size="20" :stroke-width="1.8" />
          <h2 class="m-0 truncate text-[18px]">编排服务 · {{ project.name }}</h2>
        </div>
        <span
          class="compose-services-config block truncate text-[12px]"
          :title="getComposeConfigFiles(project).join('\n')"
        >
          配置文件：{{ project.configFiles || '-' }}
        </span>
      </div>
      <div class="compose-services-toolbar">
        <NInput
          v-model:value="searchKeyword"
          clearable
          class="compose-services-search"
          placeholder="搜索服务"
        >
          <template #prefix><Search :size="16" /></template>
        </NInput>
        <NTooltip>
          <template #trigger>
            <NButton circle :loading="loading" aria-label="刷新服务" @click="load">
              <RefreshCw :size="16" />
            </NButton>
          </template>
          刷新
        </NTooltip>
      </div>
    </header>
    <NSpin :show="loading" class="compose-services-body">
      <div class="flex h-full min-h-0 flex-col px-[18px] pb-[18px]">
        <NEmpty
          v-if="services.length === 0 && !loading"
          class="my-auto"
          description="未加载到编排服务"
        />
        <NEmpty
          v-else-if="filteredServices.length === 0"
          class="my-auto"
          description="没有匹配的服务"
        />
        <div v-else class="compose-service-list app-scrollbar app-scrollbar-compact">
          <div class="compose-service-list__summary">
            共 {{ filteredServices.length }} 个服务
          </div>

          <article
            v-for="service in filteredServices"
            :key="service.id || service.name"
            class="compose-service-card"
          >
            <div class="compose-service-card__icon" aria-hidden="true">
              <Box :size="28" :stroke-width="1.8" />
            </div>

            <div class="compose-service-card__content">
              <div class="compose-service-card__heading">
                <strong :title="service.service || service.name">
                  {{ service.service || service.name || '-' }}
                </strong>
                <NTooltip trigger="hover" placement="top-start">
                  <template #trigger>
                    <NTag size="small" :type="getComposeServiceStatusPresentation(service).type">
                      {{ getComposeServiceStatusPresentation(service).label }}
                    </NTag>
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
              </div>

              <div class="compose-service-card__metadata">
                <span class="compose-service-card__meta" :title="service.name || '-'">
                  <small>容器</small>{{ service.name || '-' }}
                </span>
                <span class="compose-service-card__meta" :title="service.image || '-'">
                  <small>镜像</small>{{ service.image || '-' }}
                </span>
                <span class="compose-service-card__meta" :title="formatPorts(service.ports)">
                  <small>端口</small>{{ formatPorts(service.ports) }}
                </span>
              </div>

              <div class="compose-service-card__footer">
                <span v-if="service.id" class="compose-service-card__id" :title="service.id">
                  ID
                  <CopyableText
                    :text="service.id"
                    :display-text="service.id.slice(0, 12)"
                    success-message="已复制容器 ID。"
                    error-message="复制容器 ID 失败。"
                  />
                </span>
                <span :title="service.status || service.state || '-'">
                  {{ service.status || service.state || '-' }}
                </span>
              </div>
            </div>
          </article>
        </div>
      </div>
    </NSpin>
  </div>
</template>

<style scoped>
.compose-services-theme-dark {
  --docker-tab-card-border: rgba(148, 163, 184, 0.16);
  --docker-card-background: rgba(15, 23, 42, 0.28);
  --docker-text-secondary: rgba(226, 232, 240, 0.78);
  --docker-text-muted: rgba(203, 213, 225, 0.68);
}

.compose-services-theme-light {
  --docker-tab-card-border: rgba(148, 163, 184, 0.22);
  --docker-card-background: rgba(255, 255, 255, 0.28);
  --docker-text-secondary: rgba(71, 85, 105, 0.88);
  --docker-text-muted: rgba(100, 116, 139, 0.78);
}

.compose-services-header {
  border-bottom: 1px solid var(--docker-tab-card-border);
}

.compose-services-config,
.compose-service-list__summary,
.compose-service-card__footer {
  color: var(--docker-text-muted);
}

.compose-services-toolbar {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 8px;
}

.compose-services-search {
  width: min(280px, 34vw) !important;
  min-width: 180px;
}

.compose-services-body {
  flex: 1;
  min-height: 0;
}

.compose-services-body :deep(.n-spin-container),
.compose-services-body :deep(.n-spin-content) {
  height: 100%;
  min-height: 0;
}

.compose-service-list {
  display: flex;
  min-height: 0;
  flex: 1;
  flex-direction: column;
  gap: 12px;
  overflow: auto;
  padding: 14px 6px 8px 1px;
}

.compose-service-list__summary {
  flex: none;
  padding: 0 4px;
  font-size: 12px;
}

.compose-service-card {
  display: grid;
  min-width: 0;
  grid-template-columns: 64px minmax(0, 1fr);
  align-items: center;
  gap: 16px;
  border: 1px solid var(--docker-tab-card-border);
  border-radius: 12px;
  background: var(--docker-card-background);
  padding: 20px;
  transition:
    border-color 0.2s ease,
    box-shadow 0.2s ease,
    transform 0.2s ease;
}

.compose-service-card:hover {
  border-color: var(--app-primary-border);
  box-shadow: 0 8px 24px -20px rgba(var(--app-primary-rgb), 0.7);
  transform: translateY(-1px);
}

.compose-service-card__icon {
  display: grid;
  width: 64px;
  height: 64px;
  place-items: center;
  border-radius: 12px;
  background: var(--app-primary-soft);
  color: var(--app-primary-color);
}

.compose-service-card__content {
  min-width: 0;
}

.compose-service-card__heading {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 10px;
}

.compose-service-card__heading > strong {
  overflow: hidden;
  font-size: 17px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.compose-service-card__metadata {
  display: grid;
  min-width: 0;
  grid-template-columns: minmax(140px, 0.8fr) minmax(180px, 1.5fr) minmax(160px, 1fr);
  margin-top: 10px;
}

.compose-service-card__meta {
  min-width: 0;
  overflow: hidden;
  border-left: 1px solid var(--docker-tab-card-border);
  padding: 0 14px;
  color: var(--docker-text-secondary);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.compose-service-card__meta:first-child {
  border-left: 0;
  padding-left: 0;
}

.compose-service-card__meta small {
  margin-right: 6px;
  color: var(--docker-text-muted);
}

.compose-service-card__footer {
  display: flex;
  min-width: 0;
  margin-top: 12px;
  flex-wrap: wrap;
  gap: 6px 18px;
  font-size: 12px;
}

.compose-service-card__footer > span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.compose-service-card__id {
  display: flex;
  align-items: center;
  gap: 5px;
}

@media (max-width: 760px) {
  .compose-services-header {
    align-items: stretch;
  }

  .compose-services-header > div:first-child,
  .compose-services-toolbar {
    width: 100%;
  }

  .compose-services-search {
    min-width: 0;
    flex: 1;
    width: auto !important;
  }

  .compose-service-card {
    grid-template-columns: 48px minmax(0, 1fr);
    gap: 10px;
    padding: 14px 12px;
  }

  .compose-service-card__icon {
    width: 48px;
    height: 48px;
  }

  .compose-service-card__metadata {
    grid-template-columns: 1fr;
  }

  .compose-service-card__meta {
    border-left: 0;
    padding: 3px 0;
  }
}
</style>

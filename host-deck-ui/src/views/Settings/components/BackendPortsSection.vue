<script setup lang="ts">
import { Renew } from '@vicons/carbon'
import { onMounted, ref } from 'vue'
import { settingsApi, type BackendPortInfo } from '@/api/settings'

const ports = ref<BackendPortInfo[]>([])
const loading = ref(false)
const error = ref('')

const typeLabels: Record<BackendPortInfo['type'], string> = {
  server: '主服务',
  'port-forward': '端口转发',
  'secure-browser': '安全浏览器',
  docker: 'Docker',
}

function formatStartedAt(value: number) {
  return new Date(value).toLocaleString()
}

async function refresh() {
  if (loading.value) {
    return
  }

  loading.value = true
  error.value = ''
  try {
    const data = await settingsApi.getBackendPorts()
    ports.value = data.items
  } catch (loadError) {
    error.value = loadError instanceof Error ? loadError.message : '后端端口加载失败。'
  } finally {
    loading.value = false
  }
}

defineExpose({ refresh })
onMounted(refresh)
</script>

<template>
  <NCard title="后端端口" size="large">
    <template #header-extra>
      <NTooltip>
        <template #trigger>
          <NButton circle secondary :loading="loading" aria-label="刷新后端端口" @click="refresh">
            <template #icon>
              <NIcon><Renew /></NIcon>
            </template>
          </NButton>
        </template>
        刷新
      </NTooltip>
    </template>

    <div
      v-if="loading && ports.length === 0"
      class="flex min-h-[220px] items-center justify-center"
    >
      <NSpin size="large" />
    </div>

    <NAlert v-else-if="error" type="error" title="端口信息加载失败">
      <div class="flex flex-wrap items-center justify-between gap-[12px]">
        <span>{{ error }}</span>
        <NButton size="small" type="error" secondary :loading="loading" @click="refresh">
          重试
        </NButton>
      </div>
    </NAlert>

    <NEmpty v-else-if="ports.length === 0" class="py-[64px]" description="当前没有运行端口" />

    <div
      v-else
      class="backend-ports-list overflow-hidden border-y border-[rgba(148,163,184,0.16)]"
    >
      <div
        v-for="portInfo in ports"
        :key="portInfo.id"
        class="backend-port-row grid gap-x-[24px] gap-y-[12px] border-b border-[rgba(148,163,184,0.14)] px-[4px] py-[16px] last:border-b-0"
      >
        <div class="min-w-0">
          <div class="flex min-w-0 flex-wrap items-center gap-[8px]">
            <span class="min-w-0 break-words text-[14px] font-600">{{ portInfo.name }}</span>
            <NTag size="small" :bordered="false">{{ typeLabels[portInfo.type] }}</NTag>
            <NTag
              size="small"
              :bordered="false"
              :type="portInfo.status === 'running' ? 'success' : 'error'"
            >
              {{ portInfo.status === 'running' ? '运行中' : '异常' }}
            </NTag>
          </div>
          <div class="mt-[6px] break-all font-mono text-[13px] text-[rgba(71,85,105,0.94)]">
            {{ portInfo.host }}:{{ portInfo.port }}
          </div>
        </div>

        <div
          class="backend-port-meta min-w-0 text-[12px] leading-[1.65] text-[rgba(100,116,139,0.9)]"
        >
          <div v-if="portInfo.target" class="break-all">目标：{{ portInfo.target }}</div>
          <div v-if="portInfo.connectionId" class="break-all">
            连接 ID：{{ portInfo.connectionId }}
          </div>
          <div v-if="portInfo.activeConnections !== undefined">
            活跃连接：{{ portInfo.activeConnections }}
          </div>
          <div v-if="portInfo.startedAt !== undefined">
            启动时间：{{ formatStartedAt(portInfo.startedAt) }}
          </div>
          <div v-if="portInfo.error" class="break-words text-[rgba(239,68,68,0.96)]">
            错误：{{ portInfo.error }}
          </div>
          <div
            v-if="
              !portInfo.connectionId &&
              !portInfo.target &&
              portInfo.activeConnections === undefined &&
              portInfo.startedAt === undefined &&
              !portInfo.error
            "
          >
            ID：{{ portInfo.id }}
          </div>
        </div>
      </div>
    </div>
  </NCard>
</template>

<style scoped>
.backend-ports-list {
  container-type: inline-size;
}

.backend-port-row {
  grid-template-columns: minmax(0, 1.2fr) minmax(0, 1fr);
}

@container (max-width: 720px) {
  .backend-port-row {
    grid-template-columns: minmax(0, 1fr);
    row-gap: 10px;
  }
}
</style>

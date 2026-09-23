<script setup lang="ts">
import { computed } from 'vue'
import {
  ChevronRight,
  Container,
  Database,
  Disc3,
  Layers,
  Network,
  OctagonPause,
  RefreshCw,
  TriangleAlert,
} from '@lucide/vue'
import { LogoDocker } from '@vicons/ionicons5'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'
import type { DockerTabName } from '../hooks/dockerViewTypes'

const props = defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()

const runningProjects = computed(
  () =>
    props.controller.composeProjects.filter((project) =>
      project.status.toLowerCase().includes('running'),
    ).length,
)

const engineDetails = computed(() => [
  {
    label: '运行中容器',
    value: `${props.controller.runningContainers} / ${props.controller.containerSummary.total}`,
  },
  {
    label: '编排项目',
    value: `${runningProjects.value} / ${props.controller.composeProjects.length}`,
  },
  {
    label: '资源对象',
    value: `${
      props.controller.imageSummary.total +
      props.controller.volumes.length +
      props.controller.networks.length
    } 个`,
  },
])

const statCards = computed(() => [
  {
    label: '容器',
    sub: '运行中',
    value: props.controller.runningContainers,
    total: props.controller.containerSummary.total,
    detail: `共 ${props.controller.containerSummary.total} 个容器`,
    icon: Container,
    tab: 'containers' as DockerTabName,
  },
  {
    label: '编排项目',
    sub: '运行中',
    value: runningProjects.value,
    total: props.controller.composeProjects.length,
    detail: `共 ${props.controller.composeProjects.length} 个项目`,
    icon: Layers,
    tab: 'compose' as DockerTabName,
  },
  {
    label: '本地镜像',
    sub: '可用镜像',
    value: props.controller.imageSummary.total,
    detail: `悬空 ${props.controller.danglingImages} 个`,
    icon: Disc3,
    tab: 'images' as DockerTabName,
  },
  {
    label: '存储卷',
    sub: '数据卷',
    value: props.controller.volumes.length,
    detail: '本地存储卷',
    icon: Database,
    tab: 'volumes' as DockerTabName,
  },
])

const resourceItems = computed(() => [
  {
    label: 'Docker 网络',
    value: props.controller.networks.length,
    icon: Network,
    tab: 'networks' as DockerTabName,
  },
  {
    label: '已停止容器',
    value: props.controller.stoppedContainers,
    icon: OctagonPause,
    tab: 'containers' as DockerTabName,
  },
  {
    label: '悬空镜像',
    value: props.controller.danglingImages,
    icon: TriangleAlert,
    tab: 'images' as DockerTabName,
  },
])
</script>

<template>
  <div class="docker-overview" :class="{ 'docker-overview-dark': settingsStore.isDark }">
    <div class="overview-grid">
      <section class="ov-card ov-card-wide" aria-labelledby="ov-engine-title">
        <header class="ov-card-header">
          <h2 id="ov-engine-title">Docker 引擎</h2>
          <NTooltip>
            <template #trigger>
              <NButton
                quaternary
                circle
                size="small"
                :loading="controller.loading"
                aria-label="刷新 Docker 概览"
                @click="controller.refresh"
              >
                <template #icon><RefreshCw :size="15" /></template>
              </NButton>
            </template>
            刷新概览
          </NTooltip>
        </header>
        <div class="ov-engine">
          <div class="ov-engine-icon">
            <NIcon class="ov-engine-logo" :size="30"><LogoDocker /></NIcon>
          </div>
          <div class="ov-engine-identity">
            <h3>Docker Engine</h3>
            <div class="ov-engine-meta ov-muted">容器、镜像与编排服务均已连接</div>
          </div>
          <span class="ov-state-pill"><span class="ov-state-dot" />运行正常</span>
        </div>
        <dl class="ov-engine-details">
          <div v-for="item in engineDetails" :key="item.label">
            <dt class="ov-muted">{{ item.label }}</dt>
            <dd>{{ item.value }}</dd>
          </div>
        </dl>
      </section>

      <button
        v-for="stat in statCards"
        :key="stat.label"
        type="button"
        class="ov-card ov-stat"
        @click="controller.setActiveTab(stat.tab)"
      >
        <span class="ov-stat-head">
          <span class="ov-stat-title">{{ stat.label }}</span>
          <ChevronRight :size="14" class="ov-stat-chevron" aria-hidden="true" />
        </span>
        <span class="ov-stat-body">
          <span class="ov-stat-icon"><component :is="stat.icon" :size="20" aria-hidden="true" /></span>
          <span class="ov-stat-main">
            <span class="ov-stat-sub ov-muted">{{ stat.sub }}</span>
            <strong class="ov-stat-value">
              {{ stat.value
              }}<span v-if="stat.total !== undefined" class="ov-stat-total">/ {{ stat.total }}</span>
            </strong>
          </span>
          <span class="ov-stat-detail ov-muted">{{ stat.detail }}</span>
        </span>
      </button>

      <section class="ov-card ov-card-wide" aria-labelledby="ov-resource-title">
        <header class="ov-card-header">
          <h2 id="ov-resource-title">资源明细</h2>
          <span class="ov-health ov-muted">
            <span class="ov-state-dot" />服务响应正常
          </span>
        </header>
        <div class="ov-resource-list">
          <button
            v-for="item in resourceItems"
            :key="item.label"
            type="button"
            class="ov-resource"
            @click="controller.setActiveTab(item.tab)"
          >
            <span class="ov-resource-label ov-muted">
              <component :is="item.icon" :size="14" aria-hidden="true" />
              {{ item.label }}
            </span>
            <strong>{{ item.value }}</strong>
          </button>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.docker-overview {
  --ov-border: rgba(148, 163, 184, 0.2);
  --ov-surface: rgba(255, 255, 255, 0.72);
  --ov-header: rgba(148, 163, 184, 0.06);
  --ov-muted: #64748b;
  --ov-state: #15803d;
  display: flex;
  min-height: 100%;
  padding: 4px;
}

.docker-overview-dark {
  --ov-border: rgba(148, 163, 184, 0.13);
  --ov-surface: rgba(30, 32, 42, 0.66);
  --ov-header: rgba(255, 255, 255, 0.025);
  --ov-muted: #a1a1aa;
  --ov-state: #4ade80;
}

.overview-grid {
  display: grid;
  align-self: flex-start;
  width: 100%;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 14px;
  margin: 0;
  padding-bottom: 14px;
  container-type: inline-size;
}

.ov-muted {
  color: var(--ov-muted);
}

.ov-card {
  min-width: 0;
  overflow: hidden;
  border: 1px solid var(--ov-border);
  border-radius: var(--app-radius-card, 10px);
  background: var(--ov-surface);
  backdrop-filter: blur(16px);
}

.ov-card-wide {
  grid-column: 1 / -1;
}

.ov-card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  min-height: 45px;
  padding: 10px 18px;
  border-bottom: 1px solid var(--ov-border);
  background: var(--ov-header);
}

.ov-card-header h2 {
  margin: 0;
  font-size: 13px;
  font-weight: 650;
}

.ov-state-pill {
  display: inline-flex;
  flex-shrink: 0;
  align-items: center;
  gap: 7px;
  padding: 4px 10px;
  border-radius: 999px;
  color: var(--ov-state);
  background: rgba(34, 197, 94, 0.1);
  font-size: 12px;
  white-space: nowrap;
}

.ov-state-dot {
  width: 7px;
  height: 7px;
  flex: none;
  border-radius: 999px;
  background: currentColor;
}

.ov-engine {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 20px;
}

.ov-engine-icon {
  display: grid;
  flex-shrink: 0;
  width: 52px;
  height: 52px;
  border-radius: 12px;
  place-items: center;
  color: #fff;
  background: var(--app-primary-color, #2563eb);
}

.ov-engine-logo {
  display: flex;
  align-items: center;
  justify-content: center;
  line-height: 0;
}

.ov-engine-logo :deep(svg) {
  display: block;
}

.ov-engine-identity {
  flex: 1;
  min-width: 0;
}

.ov-engine-identity h3 {
  margin: 0 0 8px;
  font-size: 18px;
  font-weight: 700;
}

.ov-engine-meta {
  font-size: 13px;
}

.ov-engine-details {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 16px;
  margin: 0 20px;
  padding: 16px 0 20px;
  border-top: 1px solid var(--ov-border);
}

.ov-engine-details dt {
  margin-bottom: 6px;
  font-size: 12px;
}

.ov-engine-details dd {
  margin: 0;
  font-size: 13px;
  font-variant-numeric: tabular-nums;
}

.ov-stat {
  padding: 0;
  color: inherit;
  font: inherit;
  text-align: left;
  cursor: pointer;
  transition: border-color 160ms ease;
}

.ov-stat:hover {
  border-color: var(--app-primary-border, rgba(37, 99, 235, 0.55));
}

.ov-stat-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  min-height: 45px;
  padding: 10px 18px;
  border-bottom: 1px solid var(--ov-border);
  background: var(--ov-header);
}

.ov-stat-title {
  font-size: 13px;
  font-weight: 650;
}

.ov-stat-chevron {
  color: var(--ov-muted);
  transition:
    color 160ms ease,
    transform 160ms ease;
}

.ov-stat:hover .ov-stat-chevron {
  color: var(--app-primary-color, #2563eb);
  transform: translateX(2px);
}

.ov-stat-body {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 14px;
  padding: 20px;
  font-size: 12px;
}

.ov-stat-icon {
  display: grid;
  flex-shrink: 0;
  width: 40px;
  height: 40px;
  border-radius: 50%;
  place-items: center;
  color: var(--app-primary-color, #2563eb);
  background: var(--app-primary-soft, rgba(37, 99, 235, 0.16));
}

.ov-stat-main {
  min-width: 0;
}

.ov-stat-sub {
  display: block;
}

.ov-stat-value {
  display: block;
  margin-top: 4px;
  font-size: 22px;
  font-weight: 700;
  line-height: 1.2;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}

.ov-stat-total {
  margin-left: 4px;
  color: var(--ov-muted);
  font-size: 13px;
  font-weight: 400;
}

.ov-stat-detail {
  margin-left: auto;
  text-align: right;
}

.ov-health {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  white-space: nowrap;
}

.ov-health .ov-state-dot {
  color: var(--ov-state);
}

.ov-resource-list {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
  padding: 16px 20px 20px;
}

.ov-resource {
  display: flex;
  min-width: 0;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  padding: 12px 14px;
  border: 1px solid var(--ov-border);
  border-radius: var(--app-radius-item, 8px);
  color: inherit;
  background: transparent;
  font: inherit;
  cursor: pointer;
  transition: border-color 160ms ease;
}

.ov-resource:hover {
  border-color: var(--app-primary-border, rgba(37, 99, 235, 0.55));
}

.ov-resource-label {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 7px;
  font-size: 12px;
  white-space: nowrap;
}

.ov-resource-label svg {
  flex-shrink: 0;
}

.ov-resource strong {
  font-size: 16px;
  font-variant-numeric: tabular-nums;
}

@container (max-width: 720px) {
  .overview-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@container (max-width: 460px) {
  .overview-grid {
    grid-template-columns: minmax(0, 1fr);
  }

  .ov-engine {
    flex-wrap: wrap;
  }

  .ov-engine-details,
  .ov-resource-list {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>

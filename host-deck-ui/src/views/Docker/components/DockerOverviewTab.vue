<script setup lang="ts">
import { computed } from 'vue'
import { RefreshCw } from '@lucide/vue'
import { LogoDocker } from '@vicons/ionicons5'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'

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

const primaryMetrics = computed(() => [
  {
    label: '编排项目',
    value: runningProjects.value,
    total: props.controller.composeProjects.length,
    detail: '运行中',
    tab: 'compose' as const,
  },
  {
    label: '容器',
    value: props.controller.runningContainers,
    total: props.controller.containerSummary.total,
    detail: '运行中',
    tab: 'containers' as const,
  },
  {
    label: '本地镜像',
    value: props.controller.imageSummary.total,
    detail: '个镜像',
    tab: 'images' as const,
  },
  {
    label: '存储卷',
    value: props.controller.volumes.length,
    detail: '个数据卷',
    tab: 'volumes' as const,
  },
])

const secondaryMetrics = computed(() => [
  {
    label: 'Docker 网络',
    value: props.controller.networks.length,
    tab: 'networks' as const,
  },
  {
    label: '已停止容器',
    value: props.controller.stoppedContainers,
    tab: 'containers' as const,
  },
  {
    label: '悬空镜像',
    value: props.controller.danglingImages,
    tab: 'images' as const,
  },
])
</script>

<template>
  <section
    class="docker-overview"
    :class="settingsStore.isDark ? 'docker-overview--dark' : 'docker-overview--light'"
  >
    <div class="overview-glow overview-glow--top" />
    <div class="overview-glow overview-glow--bottom" />

    <header class="overview-header">
      <div class="min-w-0">
        <div class="overview-eyebrow">
          <span class="status-dot" />
          Docker Engine
        </div>
        <h3 class="overview-title">
          服务运行
          <span>正常</span>
        </h3>
        <p class="overview-description">容器、镜像与编排服务均已连接</p>
      </div>

      <NTooltip>
        <template #trigger>
          <NButton
            class="refresh-button"
            circle
            secondary
            :loading="controller.loading"
            aria-label="刷新 Docker 概览"
            @click="controller.refresh"
          >
            <template #icon><RefreshCw :size="17" /></template>
          </NButton>
        </template>
        刷新概览
      </NTooltip>
    </header>

    <div class="docker-visual" aria-hidden="true">
      <span class="visual-orbit visual-orbit--one" />
      <span class="visual-orbit visual-orbit--two" />
      <span class="visual-particle visual-particle--one" />
      <span class="visual-particle visual-particle--two" />
      <div class="visual-shadow" />
      <div class="visual-plate visual-plate--back" />
      <div class="visual-plate">
        <NIcon :size="76"><LogoDocker /></NIcon>
      </div>
    </div>

    <div class="primary-metrics" aria-label="Docker 主要指标">
      <button
        v-for="metric in primaryMetrics"
        :key="metric.label"
        type="button"
        class="primary-metric"
        @click="controller.setActiveTab(metric.tab)"
      >
        <span class="metric-label">{{ metric.label }}</span>
        <span class="metric-value">
          <strong>{{ metric.value }}</strong>
          <template v-if="metric.total !== undefined">
            <span class="metric-divider">/</span>
            <span>{{ metric.total }}</span>
          </template>
        </span>
        <span class="metric-detail">{{ metric.detail }}</span>
      </button>
    </div>

    <div class="secondary-metrics" aria-label="Docker 补充指标">
      <button
        v-for="metric in secondaryMetrics"
        :key="metric.label"
        type="button"
        class="secondary-metric"
        @click="controller.setActiveTab(metric.tab)"
      >
        <span>{{ metric.label }}</span>
        <strong>{{ metric.value }}</strong>
      </button>
      <div class="health-state">
        <span class="status-dot" />
        服务响应正常
      </div>
    </div>
  </section>
</template>

<style scoped>
.docker-overview {
  --overview-text: #172033;
  --overview-muted: #778296;
  --overview-faint: #a0a9b8;
  --overview-blue: #247cff;
  --overview-green: #19ae55;
  --overview-line: rgba(112, 131, 160, 0.14);
  --overview-surface: rgba(255, 255, 255, 0.72);
  position: relative;
  min-height: 100%;
  overflow: hidden;
  border: 1px solid rgba(148, 163, 184, 0.16);
  border-radius: 24px;
  color: var(--overview-text);
  background:
    linear-gradient(
      112deg,
      var(--overview-surface) 0%,
      var(--overview-surface) 58%,
      transparent 58%
    ),
    linear-gradient(145deg, rgba(247, 251, 255, 0.98), rgba(231, 242, 255, 0.82));
  box-shadow: 0 18px 48px rgba(46, 89, 150, 0.08);
  isolation: isolate;
}

.docker-overview--dark {
  --overview-text: #f2f6fc;
  --overview-muted: #98a6bb;
  --overview-faint: #718096;
  --overview-blue: #55a0ff;
  --overview-green: #3ddc7d;
  --overview-line: rgba(148, 163, 184, 0.14);
  --overview-surface: rgba(13, 21, 36, 0.7);
  border-color: rgba(148, 163, 184, 0.14);
  background:
    linear-gradient(
      112deg,
      var(--overview-surface) 0%,
      var(--overview-surface) 58%,
      transparent 58%
    ),
    linear-gradient(145deg, rgba(19, 31, 51, 0.98), rgba(18, 49, 89, 0.8));
  box-shadow: 0 18px 48px rgba(0, 0, 0, 0.16);
}

.overview-header {
  position: relative;
  z-index: 3;
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 24px;
  padding: 38px 40px 0;
}

.overview-eyebrow {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--overview-muted);
  font-size: 12px;
  font-weight: 650;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.status-dot {
  width: 7px;
  height: 7px;
  flex: none;
  border-radius: 999px;
  background: var(--overview-green);
  box-shadow: 0 0 0 5px color-mix(in srgb, var(--overview-green) 13%, transparent);
}

.overview-title {
  margin: 20px 0 0;
  font-size: clamp(28px, 3vw, 40px);
  font-weight: 400;
  letter-spacing: -0.045em;
  line-height: 1.1;
}

.overview-title span {
  margin-left: 7px;
  color: var(--overview-blue);
  font-weight: 720;
}

.overview-description {
  margin: 12px 0 0;
  color: var(--overview-muted);
  font-size: 13px;
}

.refresh-button {
  color: var(--overview-muted);
  backdrop-filter: blur(8px);
}

.docker-visual {
  position: absolute;
  z-index: 1;
  top: 30px;
  right: clamp(28px, 8vw, 112px);
  width: 280px;
  height: 250px;
  pointer-events: none;
}

.visual-plate {
  position: absolute;
  z-index: 3;
  top: 51px;
  left: 85px;
  display: grid;
  width: 124px;
  height: 140px;
  place-items: center;
  border: 1px solid rgba(255, 255, 255, 0.56);
  border-radius: 36px 36px 52px 52px;
  color: white;
  background: linear-gradient(145deg, #2194ff 2%, #146df1 58%, #78b8ff 100%);
  box-shadow:
    inset -10px -14px 28px rgba(255, 255, 255, 0.18),
    0 22px 40px rgba(26, 116, 239, 0.28);
  transform: perspective(420px) rotateY(-8deg) rotateZ(2deg);
  clip-path: polygon(50% 0, 96% 15%, 94% 68%, 82% 84%, 50% 100%, 18% 84%, 6% 68%, 4% 15%);
}

.visual-plate--back {
  z-index: 2;
  top: 42px;
  left: 99px;
  opacity: 0.24;
  background: #66adff;
}

.visual-orbit {
  position: absolute;
  z-index: 4;
  top: 92px;
  left: 17px;
  width: 250px;
  height: 86px;
  border: 2px solid rgba(62, 143, 245, 0.14);
  border-radius: 50%;
  transform: rotate(12deg);
}

.visual-orbit--two {
  top: 84px;
  left: 38px;
  width: 210px;
  transform: rotate(-16deg);
}

.visual-particle {
  position: absolute;
  z-index: 5;
  top: 94px;
  left: 17px;
  width: 11px;
  height: 11px;
  border-radius: 50%;
  background: #8bc8ff;
  box-shadow: 0 0 0 5px rgba(139, 200, 255, 0.16);
}

.visual-particle--two {
  top: 166px;
  left: 253px;
  width: 8px;
  height: 8px;
}

.visual-shadow {
  position: absolute;
  top: 210px;
  left: 78px;
  width: 150px;
  height: 22px;
  border-radius: 50%;
  background: rgba(64, 148, 255, 0.2);
  filter: blur(9px);
}

.primary-metrics {
  position: relative;
  z-index: 3;
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  margin-top: 126px;
  padding: 0 32px;
}

.primary-metric {
  min-width: 0;
  padding: 24px 16px 25px;
  border: 0;
  border-right: 1px solid var(--overview-line);
  color: inherit;
  background: transparent;
  text-align: left;
  cursor: pointer;
  transition: background-color 160ms ease;
}

.primary-metric:first-child {
  padding-left: 8px;
}

.primary-metric:last-child {
  border-right: 0;
}

.primary-metric:hover {
  background: color-mix(in srgb, var(--overview-blue) 5%, transparent);
}

.metric-label,
.metric-detail {
  display: block;
  color: var(--overview-muted);
}

.metric-label {
  font-size: 15px;
  font-weight: 560;
}

.metric-value {
  display: flex;
  align-items: baseline;
  margin-top: 10px;
  font-size: clamp(24px, 3vw, 34px);
  font-weight: 650;
  letter-spacing: -0.04em;
  white-space: nowrap;
}

.metric-value strong {
  color: var(--overview-green);
  font: inherit;
}

.metric-divider {
  margin: 0 3px;
  color: var(--overview-faint);
  font-weight: 400;
}

.metric-detail {
  margin-top: 7px;
  font-size: 11px;
}

.secondary-metrics {
  position: relative;
  z-index: 3;
  display: flex;
  align-items: stretch;
  margin: 0 32px 28px;
  border-top: 1px solid var(--overview-line);
}

.secondary-metric {
  display: flex;
  flex: 0 1 180px;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
  padding: 18px 16px;
  border: 0;
  color: var(--overview-muted);
  background: transparent;
  font-size: 12px;
  cursor: pointer;
}

.secondary-metric:first-child {
  padding-left: 8px;
}

.secondary-metric strong {
  color: var(--overview-text);
  font-size: 16px;
}

.health-state {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-left: auto;
  padding: 18px 8px 18px 24px;
  color: var(--overview-muted);
  font-size: 12px;
}

.overview-glow {
  position: absolute;
  z-index: 0;
  border-radius: 999px;
  pointer-events: none;
  filter: blur(4px);
}

.overview-glow--top {
  top: -190px;
  right: -80px;
  width: 520px;
  height: 420px;
  background: radial-gradient(circle, rgba(76, 155, 255, 0.2), transparent 68%);
}

.overview-glow--bottom {
  right: 12%;
  bottom: -210px;
  width: 430px;
  height: 350px;
  background: radial-gradient(circle, rgba(81, 166, 255, 0.16), transparent 66%);
}

@media (max-width: 900px) {
  .docker-visual {
    right: 2px;
    opacity: 0.72;
    transform: scale(0.82);
    transform-origin: top right;
  }

  .primary-metrics {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    margin-top: 112px;
  }

  .primary-metric:nth-child(2) {
    border-right: 0;
  }

  .primary-metric:nth-child(-n + 2) {
    border-bottom: 1px solid var(--overview-line);
  }

  .secondary-metrics {
    flex-wrap: wrap;
  }

  .health-state {
    width: 100%;
    margin-left: 0;
    border-top: 1px solid var(--overview-line);
  }
}

@media (max-width: 600px) {
  .docker-overview {
    border-radius: 18px;
    background: linear-gradient(145deg, var(--overview-surface), rgba(46, 129, 230, 0.1));
  }

  .overview-header {
    padding: 26px 22px 0;
  }

  .overview-description {
    max-width: 210px;
  }

  .docker-visual {
    top: 32px;
    right: -74px;
    opacity: 0.35;
    transform: scale(0.66);
  }

  .primary-metrics {
    margin-top: 70px;
    padding: 0 14px;
  }

  .primary-metric,
  .primary-metric:first-child {
    padding: 20px 10px;
  }

  .secondary-metrics {
    margin: 0 14px 18px;
  }

  .secondary-metric,
  .secondary-metric:first-child {
    flex-basis: 50%;
    padding: 15px 10px;
  }
}
</style>

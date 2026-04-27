<script setup lang="ts">
import { Grid, List } from '@vicons/carbon'
import type { DockerImage } from '@/api/docker'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'

defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()

function getImageStatus(image: DockerImage) {
  if (image.dangling) {
    return '悬空'
  }

  if (image.inUse) {
    return '使用中'
  }

  return '普通'
}

function getImageStatusType(image: DockerImage) {
  if (image.dangling) {
    return 'warning'
  }

  if (image.inUse) {
    return 'success'
  }

  return 'default'
}

function getImageName(image: DockerImage) {
  return `${image.repository}:${image.tag}`
}
</script>

<template>
  <div class="flex flex-col" :class="settingsStore.isDark ? 'docker-theme-dark' : 'docker-theme-light'">
    <div class="mb-[12px] flex flex-wrap items-start justify-between gap-[12px]">
      <div class="text-[13px]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.68)]' : 'text-[rgba(71,85,105,0.88)]'">支持镜像重新打标签、查看构建历史和引用容器。</div>
      <NButtonGroup size="small">
        <NButton
          :type="controller.imageViewMode === 'card' ? 'primary' : 'default'"
          title="卡片视图"
          aria-label="卡片视图"
          @click="controller.setImageViewMode('card')"
        >
          <template #icon>
            <NIcon><Grid /></NIcon>
          </template>
        </NButton>
        <NButton
          :type="controller.imageViewMode === 'table' ? 'primary' : 'default'"
          title="表格视图"
          aria-label="表格视图"
          @click="controller.setImageViewMode('table')"
        >
          <template #icon>
            <NIcon><List /></NIcon>
          </template>
        </NButton>
      </NButtonGroup>
    </div>

    <div v-if="controller.imageViewMode === 'card'" class="docker-card-shell">
      <NEmpty v-if="controller.images.length === 0" description="暂无镜像" />

      <div v-else class="docker-card-grid">
        <NCard
          v-for="image in controller.images"
          :key="image.id"
          class="docker-card"
          content-class="docker-card-content"
          size="small"
          :bordered="false"
        >
          <template #header>
            <div class="min-w-0">
              <div class="truncate text-[15px] font-600" :title="getImageName(image)">{{ getImageName(image) }}</div>
              <div class="mt-[4px] truncate text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.58)]' : 'text-[rgba(100,116,139,0.88)]'" :title="image.id">
                {{ image.id.slice(0, 18) }}
              </div>
            </div>
          </template>

          <template #header-extra>
            <NTag round size="small" :type="getImageStatusType(image)">{{ getImageStatus(image) }}</NTag>
          </template>

          <div class="docker-card-fields">
            <div class="docker-card-field wide">
              <span>仓库</span>
              <strong :title="image.repository">{{ image.repository }}</strong>
            </div>
            <div class="docker-card-field">
              <span>标签</span>
              <strong :title="image.tag">{{ image.tag }}</strong>
            </div>
            <div class="docker-card-field">
              <span>大小</span>
              <strong>{{ image.size }}</strong>
            </div>
            <div class="docker-card-field wide">
              <span>创建时间</span>
              <strong>{{ controller.formatTime(image.createdAt) }}</strong>
            </div>
          </div>

          <template #footer>
            <div class="docker-card-actions">
              <NButton size="tiny" quaternary @click="controller.openImageTagDialog(image)">Tag</NButton>
              <NButton size="tiny" quaternary @click="controller.viewImageHistory(image)">历史</NButton>
              <NButton size="tiny" quaternary @click="controller.viewImageRefs(image)">引用</NButton>
              <NButton size="tiny" quaternary type="error" @click="controller.confirmRemoveImage(image)">删除</NButton>
            </div>
          </template>
        </NCard>
      </div>

      <div v-if="controller.imageTotal > 0" class="docker-card-pagination">
        <NPagination
          :page="controller.imagePagination.page"
          :page-size="controller.imagePagination.pageSize"
          :item-count="controller.imagePagination.itemCount"
          :page-sizes="controller.imagePagination.pageSizes"
          show-size-picker
          @update:page="controller.handleImagePageChange"
          @update:page-size="controller.handleImagePageSizeChange"
        />
      </div>
    </div>

    <div v-else class="docker-table-shell">
      <NDataTable
        class="docker-table"
        :single-line="false"
        :columns="controller.imageColumns"
        :data="controller.images"
        :pagination="controller.imagePagination"
        remote
        size="small"
        @update:page="controller.handleImagePageChange"
        @update:page-size="controller.handleImagePageSizeChange"
      />
    </div>
  </div>
</template>

<style scoped>
.docker-theme-dark {
  --docker-card-border: rgba(148, 163, 184, 0.16);
  --docker-card-bg: linear-gradient(145deg, rgba(15, 23, 42, 0.72), rgba(30, 41, 59, 0.46));
  --docker-card-shadow: 0 18px 42px rgba(2, 6, 23, 0.18);
  --docker-card-border-hover: rgba(96, 165, 250, 0.36);
  --docker-card-bg-hover: linear-gradient(145deg, rgba(15, 23, 42, 0.84), rgba(30, 64, 175, 0.32));
  --docker-card-field-bg: rgba(15, 23, 42, 0.38);
  --docker-card-label-color: rgba(226, 232, 240, 0.52);
  --docker-card-value-color: rgba(248, 250, 252, 0.9);
  --docker-scrollbar-thumb: rgba(148, 163, 184, 0.34);
  --docker-scrollbar-thumb-hover: rgba(96, 165, 250, 0.52);
}

.docker-theme-light {
  --docker-card-border: rgba(148, 163, 184, 0.22);
  --docker-card-bg: linear-gradient(145deg, rgba(255, 255, 255, 0.96), rgba(241, 245, 249, 0.92));
  --docker-card-shadow: 0 18px 40px rgba(15, 23, 42, 0.08);
  --docker-card-border-hover: rgba(59, 130, 246, 0.3);
  --docker-card-bg-hover: linear-gradient(145deg, rgba(255, 255, 255, 0.98), rgba(219, 234, 254, 0.9));
  --docker-card-field-bg: rgba(241, 245, 249, 0.92);
  --docker-card-label-color: rgba(100, 116, 139, 0.9);
  --docker-card-value-color: rgba(30, 41, 59, 0.92);
  --docker-scrollbar-thumb: rgba(100, 116, 139, 0.26);
  --docker-scrollbar-thumb-hover: rgba(59, 130, 246, 0.42);
}

.docker-card-shell,
.docker-table-shell {
  flex: none;
  overflow: visible;
}

.docker-card-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, 340px);
  gap: 12px;
  justify-content: start;
}

.docker-card {
  width: 340px;
  border: 1px solid var(--docker-card-border);
  background: var(--docker-card-bg);
  box-shadow: var(--docker-card-shadow);
}

.docker-card:hover {
  border-color: var(--docker-card-border-hover);
  background: var(--docker-card-bg-hover);
}

.docker-card :deep(.docker-card-content) {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.docker-card-fields {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
}

.docker-card-field {
  min-width: 0;
  border-radius: 12px;
  background: var(--docker-card-field-bg);
  padding: 9px 10px;
}

.docker-card-field.wide {
  grid-column: 1 / -1;
}

.docker-card-field span {
  display: block;
  margin-bottom: 4px;
  color: var(--docker-card-label-color);
  font-size: 12px;
}

.docker-card-field strong {
  display: block;
  overflow: hidden;
  color: var(--docker-card-value-color);
  font-size: 13px;
  font-weight: 500;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.docker-card-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.docker-card-pagination {
  display: flex;
  justify-content: flex-end;
  margin-top: 14px;
}

.docker-table {
  min-width: 100%;
}

.docker-table-shell :deep(.n-data-table-base-table-body) {
  scrollbar-width: thin;
  scrollbar-color: var(--docker-scrollbar-thumb) transparent;
}

.docker-table-shell :deep(.n-data-table-base-table-body::-webkit-scrollbar) {
  width: 10px;
  height: 10px;
}

.docker-table-shell :deep(.n-data-table-base-table-body::-webkit-scrollbar-track),
.docker-table-shell :deep(.n-data-table-base-table-body::-webkit-scrollbar-corner) {
  background: transparent;
}

.docker-table-shell :deep(.n-data-table-base-table-body::-webkit-scrollbar-thumb) {
  border: 3px solid transparent;
  border-radius: 999px;
  background-clip: padding-box;
  background-color: var(--docker-scrollbar-thumb);
}

.docker-table-shell:hover :deep(.n-data-table-base-table-body::-webkit-scrollbar-thumb) {
  background-color: var(--docker-scrollbar-thumb-hover);
}

.docker-table-shell :deep(.container-action-popover) {
  max-width: 260px;
}

@media (max-width: 640px) {
  .docker-card-grid {
    grid-template-columns: 1fr;
  }

  .docker-card {
    width: 100%;
  }

  .docker-card-fields {
    grid-template-columns: 1fr;
  }
}
</style>

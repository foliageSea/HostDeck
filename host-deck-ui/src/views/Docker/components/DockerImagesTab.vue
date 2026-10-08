<script setup lang="ts">
import { computed, ref } from 'vue'
import { Download, Upload } from '@vicons/carbon'
import { ChevronDown, Ellipsis, Layers3, RefreshCw, Search } from '@lucide/vue'
import type { DockerImage } from '@/api/docker'
import CopyableText from '@/components/common/CopyableText.vue'
import type { DockerViewController } from '../hooks/useDockerView'
import DockerTabToolbar from './DockerTabToolbar.vue'

const props = defineProps<{
  controller: DockerViewController
}>()

const imageImportInputRef = ref<HTMLInputElement | null>(null)

const imagePruneOptions = computed(() => [
  { key: 'prune-dangling-images', label: '清理悬空镜像' },
  { key: 'prune-unused-images', label: '清理无引用镜像' },
  { key: 'divider', type: 'divider' },
  { key: 'prune-build-cache', label: '清理构建缓存' },
  { key: 'prune-build-cache-all', label: '清理全部缓存' },
])

function handleImagePruneAction(key: string) {
  switch (key) {
    case 'prune-dangling-images':
      props.controller.confirmPruneImages(false)
      break
    case 'prune-unused-images':
      props.controller.confirmPruneImages(true)
      break
    case 'prune-build-cache':
      props.controller.confirmPruneBuildCache(false)
      break
    case 'prune-build-cache-all':
      props.controller.confirmPruneBuildCache(true)
      break
  }
}

function openImageImportPicker() {
  if (props.controller.importingImage) {
    return
  }

  imageImportInputRef.value?.click()
}

async function handleImageImportChange(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) {
    return
  }

  try {
    await props.controller.importImage(file)
  } finally {
    input.value = ''
  }
}

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

function getImageMoreActionOptions(image: DockerImage) {
  return [
    { key: 'history', label: '历史' },
    { key: 'refs', label: '引用' },
    { key: 'remove', label: '删除', disabled: image.inUse },
  ]
}

function handleImageMoreAction(image: DockerImage, action: string) {
  switch (action) {
    case 'history':
      props.controller.viewImageHistory(image)
      break
    case 'refs':
      props.controller.viewImageRefs(image)
      break
    case 'remove':
      props.controller.confirmRemoveImage(image)
      break
  }
}
</script>

<template>
  <div class="flex h-full min-h-0 flex-col overflow-hidden">
    <input
      ref="imageImportInputRef"
      type="file"
      hidden
      accept=".tar,.tar.gz,.tgz,application/x-tar,application/gzip,application/x-gzip"
      @change="handleImageImportChange"
    />

    <DockerTabToolbar>
      <template #left>
        <NButton type="primary" @click="controller.openPullImageDialog">
          <template #icon>
            <NIcon><Download /></NIcon>
          </template>
          拉取镜像
        </NButton>
        <NButton :loading="controller.importingImage" @click="openImageImportPicker">
          <template #icon>
            <NIcon><Upload /></NIcon>
          </template>
          导入镜像
        </NButton>
      </template>

      <template #actions>
        <NInput
          :value="controller.imageSearchKeyword"
          clearable
          class="image-search-input"
          placeholder="搜索镜像"
          @update:value="controller.setImageSearchKeyword"
        >
          <template #prefix><Search :size="16" /></template>
        </NInput>
        <NTooltip>
          <template #trigger>
            <NButton
              circle
              :loading="controller.loading"
              aria-label="刷新镜像"
              @click="controller.refreshImages"
            >
              <template #icon><RefreshCw :size="16" /></template>
            </NButton>
          </template>
          刷新
        </NTooltip>
        <NDropdown trigger="click" :options="imagePruneOptions" @select="handleImagePruneAction">
          <NButton>
            <span class="flex items-center gap-[4px]">清理 <ChevronDown :size="14" /></span>
          </NButton>
        </NDropdown>
      </template>
    </DockerTabToolbar>

    <NEmpty v-if="controller.images.length === 0" class="my-auto" />
    <div v-else class="image-list app-scrollbar app-scrollbar-compact">
      <div class="image-list__summary">共 {{ controller.imageTotal }} 个镜像</div>

      <article
        v-for="image in controller.images"
        :key="`${image.id}:${image.repository}:${image.tag}`"
        class="image-card"
      >
        <div class="image-card__icon" aria-hidden="true">
          <Layers3 :size="28" :stroke-width="1.8" />
        </div>

        <div class="image-card__content">
          <div class="image-card__heading">
            <strong :title="getImageName(image)">{{ getImageName(image) }}</strong>
            <NTag size="small" :type="getImageStatusType(image)">
              {{ getImageStatus(image) }}
            </NTag>
          </div>

          <div class="image-card__metadata">
            <span class="image-card__meta image-card__meta--wide" :title="image.repository">
              <small>仓库</small>{{ image.repository || '-' }}
            </span>
            <span class="image-card__meta" :title="image.tag">
              <small>标签</small>{{ image.tag || '-' }}
            </span>
            <span class="image-card__meta"> <small>大小</small>{{ image.size || '-' }} </span>
          </div>

          <div class="image-card__footer">
            <span class="image-card__id" :title="image.id">
              ID
              <CopyableText
                :text="image.id"
                :display-text="image.id.slice(0, 18)"
                success-message="已复制镜像 ID。"
                error-message="复制镜像 ID 失败。"
              />
            </span>
            <span>创建于 {{ controller.formatTime(image.createdAt) }}</span>
          </div>
        </div>

        <div class="image-card__actions">
          <NButton text type="primary" @click="controller.openImageTagDialog(image)">标签</NButton>
          <NButton
            text
            type="primary"
            :loading="controller.imageExportingMap[image.id]"
            @click="controller.exportImage(image)"
          >
            导出
          </NButton>
          <NDropdown
            trigger="click"
            :options="getImageMoreActionOptions(image)"
            @select="(action: string | number) => handleImageMoreAction(image, String(action))"
          >
            <NButton quaternary circle aria-label="更多镜像操作">
              <Ellipsis :size="19" />
            </NButton>
          </NDropdown>
        </div>
      </article>
    </div>

    <div v-if="controller.imageTotal > 0" class="image-pagination">
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
</template>

<style scoped>
.image-search-input {
  width: min(320px, 36vw) !important;
  min-width: 200px;
}

.image-list {
  display: flex;
  min-height: 0;
  flex: 1;
  flex-direction: column;
  gap: 12px;
  overflow: auto;
  padding: 1px 6px 8px 1px;
}

.image-list__summary {
  display: flex;
  flex: none;
  padding: 0 4px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
  font-size: 12px;
}

.image-card {
  display: grid;
  min-width: 0;
  grid-template-columns: 64px minmax(0, 1fr) auto;
  align-items: center;
  gap: 16px;
  border: 1px solid var(--docker-tab-card-border, rgba(148, 163, 184, 0.2));
  border-radius: 12px;
  background: var(--docker-card-background, transparent);
  padding: 20px;
  transition:
    border-color 0.2s ease,
    box-shadow 0.2s ease,
    transform 0.2s ease;
}

.image-card:hover {
  border-color: var(--app-primary-border);
  box-shadow: 0 8px 24px -20px rgba(var(--app-primary-rgb), 0.7);
  transform: translateY(-1px);
}

.image-card__icon {
  display: grid;
  width: 64px;
  height: 64px;
  place-items: center;
  border-radius: 12px;
  background: var(--app-primary-soft);
  color: var(--app-primary-color);
}

.image-card__content {
  min-width: 0;
}

.image-card__heading {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 10px;
}

.image-card__heading > strong {
  overflow: hidden;
  font-size: 17px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.image-card__metadata {
  display: grid;
  min-width: 0;
  grid-template-columns: minmax(180px, 1.6fr) minmax(100px, 0.7fr) minmax(90px, 0.5fr);
  margin-top: 10px;
}

.image-card__meta {
  min-width: 0;
  overflow: hidden;
  border-left: 1px solid var(--docker-tab-card-border, rgba(148, 163, 184, 0.2));
  padding: 0 14px;
  color: var(--docker-text-secondary, rgba(71, 85, 105, 0.88));
  text-overflow: ellipsis;
  white-space: nowrap;
}

.image-card__meta:first-child {
  border-left: 0;
  padding-left: 0;
}

.image-card__meta small {
  margin-right: 6px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
}

.image-card__footer {
  display: flex;
  min-width: 0;
  margin-top: 12px;
  flex-wrap: wrap;
  gap: 6px 18px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
  font-size: 12px;
}

.image-card__footer > span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.image-card__id {
  display: flex;
  align-items: center;
  gap: 5px;
}

.image-card__actions {
  display: flex;
  flex: none;
  align-items: center;
  gap: 16px;
}

.image-pagination {
  display: flex;
  flex: none;
  justify-content: flex-end;
  border-top: 1px solid var(--docker-tab-card-border, rgba(148, 163, 184, 0.2));
  padding-top: 10px;
}

@media (max-width: 900px) {
  .image-card {
    grid-template-columns: 56px minmax(0, 1fr);
  }

  .image-card__icon {
    width: 56px;
    height: 56px;
  }

  .image-card__actions {
    grid-column: 2;
    justify-content: flex-end;
  }
}

@media (max-width: 640px) {
  .image-search-input {
    width: calc(100% - 90px) !important;
    min-width: 0;
  }

  .image-card {
    grid-template-columns: 48px minmax(0, 1fr);
    gap: 10px;
    padding: 14px 12px;
  }

  .image-card__icon {
    width: 48px;
    height: 48px;
  }

  .image-card__metadata {
    grid-template-columns: 1fr;
  }

  .image-card__meta {
    border-left: 0;
    padding: 3px 0;
  }

  .image-card__actions {
    grid-column: 2;
    gap: 14px;
  }

  .image-card__footer span:last-child {
    display: none;
  }
}
</style>

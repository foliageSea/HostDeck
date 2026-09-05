<script setup lang="ts">
import { computed, ref } from 'vue'
import { Download, Upload } from '@vicons/carbon'
import type { DockerImage } from '@/api/docker'
import type { DockerViewController } from '../hooks/useDockerView'
import DockerResourceTable from './DockerResourceTable.vue'
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
        <div class="flex items-center gap-1">
          <NInput
            :value="controller.imageSearchKeyword"
            clearable
            class="w-[min(220px,60vw)] lt-sm:w-full"
            placeholder="搜索镜像"
            @update:value="controller.setImageSearchKeyword"
          />
        </div>
      </template>

      <template #actions>
        <div class="flex min-w-0 items-center gap-[6px]">
          <NButton type="primary" @click="controller.openPullImageDialog">
            <template #icon>
              <NIcon><Download /></NIcon>
            </template>
            拉取
          </NButton>
        </div>
        <NButton type="primary" :loading="controller.importingImage" @click="openImageImportPicker">
          <template #icon>
            <NIcon>
              <Upload />
            </NIcon>
          </template>
          导入镜像
        </NButton>
        <NButton quaternary :loading="controller.loading" @click="controller.refreshImages"
          >刷新</NButton
        >
        <NDropdown trigger="click" :options="imagePruneOptions" @select="handleImagePruneAction">
          <NButton quaternary>清理</NButton>
        </NDropdown>
      </template>

      <template #meta>
        <NTag round size="small">镜像 {{ controller.imageSummary.total }}</NTag>
        <NTag round size="small"
          >显示 {{ controller.imageTotal }} / {{ controller.imageSummary.total }}</NTag
        >
      </template>
    </DockerTabToolbar>

    <NEmpty v-if="controller.images.length === 0" />
    <DockerResourceTable v-else min-width="1240px">
      <thead>
        <tr>
          <th style="width: 260px">镜像</th>
          <th style="width: 110px">状态</th>
          <th style="width: 320px">仓库</th>
          <th style="width: 130px">标签</th>
          <th style="width: 100px">大小</th>
          <th style="width: 190px">创建时间</th>
          <th class="docker-table-actions-column" style="width: 190px; text-align: right">操作</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="image in controller.images" :key="image.id">
          <td>
            <span class="docker-table-primary" :title="getImageName(image)">{{
              getImageName(image)
            }}</span
            ><span class="docker-table-secondary" :title="image.id">{{
              image.id.slice(0, 18)
            }}</span>
          </td>
          <td>
            <NTag round size="small" :type="getImageStatusType(image)">{{
              getImageStatus(image)
            }}</NTag>
          </td>
          <td>
            <span class="docker-table-primary" :title="image.repository">{{
              image.repository
            }}</span>
          </td>
          <td>
            <span class="docker-table-primary" :title="image.tag">{{ image.tag }}</span>
          </td>
          <td>{{ image.size }}</td>
          <td class="docker-table-nowrap">{{ controller.formatTime(image.createdAt) }}</td>
          <td class="docker-table-actions-column">
            <div class="docker-table-actions">
              <NButton size="tiny" quaternary @click="controller.openImageTagDialog(image)"
                >标签</NButton
              >
              <NButton
                size="tiny"
                quaternary
                :loading="controller.imageExportingMap[image.id]"
                @click="controller.exportImage(image)"
                >导出</NButton
              >
              <NDropdown
                trigger="click"
                :options="getImageMoreActionOptions(image)"
                @select="(action: string | number) => handleImageMoreAction(image, String(action))"
              >
                <NButton size="tiny" quaternary>更多</NButton>
              </NDropdown>
            </div>
          </td>
        </tr>
      </tbody>
      <template v-if="controller.imageTotal > 0" #footer>
        <NPagination
          :page="controller.imagePagination.page"
          :page-size="controller.imagePagination.pageSize"
          :item-count="controller.imagePagination.itemCount"
          :page-sizes="controller.imagePagination.pageSizes"
          show-size-picker
          @update:page="controller.handleImagePageChange"
          @update:page-size="controller.handleImagePageSizeChange"
        />
      </template>
    </DockerResourceTable>
  </div>
</template>

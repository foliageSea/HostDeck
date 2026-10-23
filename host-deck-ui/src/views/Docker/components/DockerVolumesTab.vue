<script setup lang="ts">
import { reactive, ref } from 'vue'
import { Add } from '@vicons/carbon'
import { Ellipsis, HardDrive, RefreshCw, Search } from '@lucide/vue'
import type { DockerVolume } from '@/api/docker'
import type { DockerViewController } from '../hooks/useDockerView'
import DockerTabToolbar from './DockerTabToolbar.vue'

const props = defineProps<{
  controller: DockerViewController
}>()

const createVisible = ref(false)
const createSubmitting = ref(false)
const createOptionsText = ref('')
const createLabelsText = ref('')
const volumeDriverOptions = [{ label: 'local', value: 'local' }]
const createForm = reactive({
  name: '',
  driver: 'local',
})

function openCreateDialog() {
  createForm.name = ''
  createForm.driver = 'local'
  createOptionsText.value = ''
  createLabelsText.value = ''
  createVisible.value = true
}

function parseKeyValueMap(value: string) {
  return Object.fromEntries(
    value
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        const index = line.indexOf('=')
        if (index < 1 || index === line.length - 1) {
          return null
        }

        return [line.slice(0, index).trim(), line.slice(index + 1).trim()] as const
      })
      .filter((entry): entry is readonly [string, string] =>
        Boolean(entry && entry[0] && entry[1]),
      ),
  )
}

async function submitCreate() {
  if (!createForm.name.trim()) {
    return
  }

  createSubmitting.value = true
  try {
    const success = await props.controller.createVolume({
      name: createForm.name.trim(),
      driver: createForm.driver.trim() || 'local',
      options: parseKeyValueMap(createOptionsText.value),
      labels: parseKeyValueMap(createLabelsText.value),
    })
    if (success) {
      createVisible.value = false
    }
  } finally {
    createSubmitting.value = false
  }
}

function getVolumeUsageTagType(volume: DockerVolume) {
  return volume.refCount > 0 ? ('success' as const) : ('default' as const)
}

function getVolumeUsageLabel(volume: DockerVolume) {
  return volume.refCount > 0 ? '使用中' : '未使用'
}

function getVolumeUsageTitle(volume: DockerVolume) {
  const names = volume.usedBy ?? []
  if (names.length) {
    return `使用中的容器：\n${names.join('\n')}`
  }

  return volume.refCount > 0 ? `被 ${volume.refCount} 个容器使用` : '没有容器引用该存储卷'
}

function getVolumeMoreActionOptions(volume: DockerVolume) {
  return [{ key: 'remove', label: '删除', disabled: volume.refCount > 0 }]
}

function handleVolumeMoreAction(volume: DockerVolume, action: string) {
  if (action === 'remove') {
    props.controller.confirmRemoveVolume(volume)
  }
}
</script>

<template>
  <div class="flex h-full min-h-0 flex-col overflow-hidden">
    <DockerTabToolbar>
      <template #left>
        <NButton type="primary" @click="openCreateDialog">
          <template #icon>
            <NIcon>
              <Add />
            </NIcon>
          </template>
          新建存储卷
        </NButton>
      </template>

      <template #actions>
        <NInput
          v-model:value="controller.volumeSearchKeyword"
          clearable
          class="volume-search-input"
          placeholder="搜索存储卷"
        >
          <template #prefix><Search :size="16" /></template>
        </NInput>
        <NTooltip>
          <template #trigger>
            <NButton
              circle
              :loading="controller.loading"
              aria-label="刷新存储卷"
              @click="controller.refreshVolumes"
            >
              <template #icon><RefreshCw :size="16" /></template>
            </NButton>
          </template>
          刷新
        </NTooltip>
        <NButton @click="controller.confirmPruneVolumes">清理未使用</NButton>
      </template>
    </DockerTabToolbar>

    <NEmpty v-if="controller.filteredVolumes.length === 0" class="my-auto" />
    <div v-else class="volume-list app-scrollbar app-scrollbar-compact">
      <div class="volume-list__summary">共 {{ controller.filteredVolumes.length }} 个存储卷</div>

      <article v-for="volume in controller.filteredVolumes" :key="volume.name" class="volume-card">
        <div class="volume-card__icon" aria-hidden="true">
          <HardDrive :size="28" :stroke-width="1.8" />
        </div>

        <div class="volume-card__content">
          <div class="volume-card__heading">
            <strong :title="volume.name">{{ volume.name }}</strong>
            <NTag size="small">{{ volume.driver }}</NTag>
            <NTag
              size="small"
              :type="getVolumeUsageTagType(volume)"
              :title="getVolumeUsageTitle(volume)"
            >
              {{ getVolumeUsageLabel(volume) }}
            </NTag>
          </div>

          <div class="volume-card__metadata">
            <span class="volume-card__meta"> <small>作用域</small>{{ volume.scope || '-' }} </span>
            <span class="volume-card__meta"> <small>引用</small>{{ volume.refCount }} </span>
            <span
              class="volume-card__meta volume-card__meta--wide"
              :title="volume.mountpoint || '暂无挂载点'"
            >
              <small>挂载点</small>{{ volume.mountpoint || '-' }}
            </span>
          </div>

          <div class="volume-card__footer">
            <span>创建于 {{ controller.formatTime(volume.createdAt) }}</span>
          </div>
        </div>

        <div class="volume-card__actions">
          <NButton
            text
            type="primary"
            :disabled="!volume.mountpoint"
            @click="controller.openVolumeDirectory(volume)"
          >
            打开目录
          </NButton>
          <NButton text type="primary" @click="controller.viewVolumeInspect(volume)">检查</NButton>
          <NDropdown
            trigger="click"
            :options="getVolumeMoreActionOptions(volume)"
            @select="(action: string | number) => handleVolumeMoreAction(volume, String(action))"
          >
            <NButton quaternary circle aria-label="更多存储卷操作">
              <Ellipsis :size="19" />
            </NButton>
          </NDropdown>
        </div>
      </article>
    </div>

    <NModal
      v-model:show="createVisible"
      preset="card"
      title="新建 Docker 存储卷"
      style="width: min(560px, 92vw)"
    >
      <NForm label-placement="top">
        <NFormItem label="存储卷名称">
          <NInput v-model:value="createForm.name" placeholder="例如 app-data" />
        </NFormItem>
        <NFormItem label="驱动">
          <NSelect v-model:value="createForm.driver" :options="volumeDriverOptions" />
        </NFormItem>
        <NFormItem label="Driver Options">
          <NInput
            v-model:value="createOptionsText"
            type="textarea"
            :rows="3"
            placeholder="每行一条 key=value，例如 type=nfs"
          />
        </NFormItem>
        <NFormItem label="Labels">
          <NInput
            v-model:value="createLabelsText"
            type="textarea"
            :rows="3"
            placeholder="每行一条 key=value，例如 app=ssh-tool"
          />
        </NFormItem>
      </NForm>
      <template #action>
        <NSpace justify="end">
          <NButton @click="createVisible = false">取消</NButton>
          <NButton type="primary" :loading="createSubmitting" @click="submitCreate">创建</NButton>
        </NSpace>
      </template>
    </NModal>
  </div>
</template>

<style scoped>
.volume-search-input {
  width: min(320px, 36vw) !important;
  min-width: 200px;
}

.volume-list {
  display: flex;
  min-height: 0;
  flex: 1;
  flex-direction: column;
  gap: 12px;
  overflow: auto;
  padding: 1px 6px 8px 1px;
}

.volume-list__summary {
  display: flex;
  flex: none;
  padding: 0 4px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
  font-size: 12px;
}

.volume-card {
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

.volume-card:hover {
  border-color: var(--app-primary-border);
  box-shadow: 0 8px 24px -20px rgba(var(--app-primary-rgb), 0.7);
  transform: translateY(-1px);
}

.volume-card__icon {
  display: grid;
  width: 64px;
  height: 64px;
  place-items: center;
  border-radius: 12px;
  background: var(--app-primary-soft);
  color: var(--app-primary-color);
}

.volume-card__content {
  min-width: 0;
}

.volume-card__heading {
  display: flex;
  min-width: 0;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}

.volume-card__heading > strong {
  overflow: hidden;
  max-width: 100%;
  font-size: 17px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.volume-card__metadata {
  display: grid;
  min-width: 0;
  grid-template-columns: minmax(90px, 0.55fr) minmax(80px, 0.4fr) minmax(240px, 2fr);
  margin-top: 10px;
}

.volume-card__meta {
  min-width: 0;
  overflow: hidden;
  border-left: 1px solid var(--docker-tab-card-border, rgba(148, 163, 184, 0.2));
  padding: 0 14px;
  color: var(--docker-text-secondary, rgba(71, 85, 105, 0.88));
  text-overflow: ellipsis;
  white-space: nowrap;
}

.volume-card__meta:first-child {
  border-left: 0;
  padding-left: 0;
}

.volume-card__meta small {
  margin-right: 6px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
}

.volume-card__footer {
  display: flex;
  min-width: 0;
  margin-top: 12px;
  flex-wrap: wrap;
  gap: 6px 18px;
  color: var(--docker-text-muted, rgba(100, 116, 139, 0.78));
  font-size: 12px;
}

.volume-card__footer > span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.volume-card__actions {
  display: flex;
  flex: none;
  align-items: center;
  gap: 16px;
}

@media (max-width: 1100px) {
  .volume-card {
    grid-template-columns: 56px minmax(0, 1fr);
  }

  .volume-card__icon {
    width: 56px;
    height: 56px;
  }

  .volume-card__actions {
    grid-column: 2;
    justify-content: flex-end;
  }

  .volume-card__metadata {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px 0;
  }

  .volume-card__meta:nth-child(3) {
    border-left: 0;
    padding-left: 0;
  }
}

@media (max-width: 640px) {
  .volume-search-input {
    width: calc(100% - 90px) !important;
    min-width: 0;
  }

  .volume-card {
    grid-template-columns: 48px minmax(0, 1fr);
    gap: 10px;
    padding: 14px 12px;
  }

  .volume-card__icon {
    width: 48px;
    height: 48px;
  }

  .volume-card__metadata {
    grid-template-columns: 1fr;
  }

  .volume-card__meta,
  .volume-card__meta:nth-child(3) {
    border-left: 0;
    padding: 3px 0;
  }

  .volume-card__actions {
    grid-column: 2;
    gap: 14px;
  }
}
</style>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useSettingsStore } from '@/stores/settings'
import type { DockerViewController } from '../hooks/useDockerView'
import DockerTabToolbar from './DockerTabToolbar.vue'

const props = defineProps<{
  controller: DockerViewController
}>()

const settingsStore = useSettingsStore()
const createVisible = ref(false)
const createSubmitting = ref(false)
const createOptionsText = ref('')
const createLabelsText = ref('')
const volumeDriverOptions = [
  { label: 'local', value: 'local' },
]
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
      .filter((entry): entry is readonly [string, string] => Boolean(entry && entry[0] && entry[1])),
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
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-[12px] overflow-hidden" :class="settingsStore.isDark ? 'docker-theme-dark' : 'docker-theme-light'">
    <DockerTabToolbar>
      <template #left>
        <NInput
          v-model:value="controller.volumeSearchKeyword"
          clearable
          class="w-[min(220px,60vw)] lt-sm:w-full"
          placeholder="搜索存储卷"
        />
      </template>

      <template #actions>
        <NButton type="primary" @click="openCreateDialog">新建存储卷</NButton>
        <NButton quaternary :loading="controller.loading" @click="controller.refreshVolumes">刷新存储卷</NButton>
        <NButton quaternary @click="controller.confirmPruneVolumes">清理未使用</NButton>
      </template>

      <template #meta>
        <NTag round size="small">显示 {{ controller.filteredVolumes.length }} / {{ controller.volumes.length }}</NTag>
      </template>
    </DockerTabToolbar>

    <NEmpty v-if="controller.filteredVolumes.length === 0" />

    <div v-else class="docker-card-list">
      <NCard
        v-for="volume in controller.filteredVolumes"
        :key="volume.name"
        class="docker-card"
        content-class="docker-card-content"
        size="small"
        :bordered="false"
      >
        <template #header>
          <div class="min-w-0">
            <div class="truncate text-[15px] font-600" :title="volume.name">{{ volume.name }}</div>
            <div class="mt-[4px] truncate text-[12px]" :class="settingsStore.isDark ? 'text-[rgba(226,232,240,0.58)]' : 'text-[rgba(100,116,139,0.88)]'">
              {{ volume.driver }} / {{ volume.scope }}
            </div>
          </div>
        </template>

        <template #header-extra>
          <NTag round size="small" :type="volume.refCount > 0 ? 'success' : 'default'">
            引用 {{ volume.refCount }}
          </NTag>
        </template>

        <div class="docker-card-fields">
          <div class="docker-card-field">
            <span>驱动</span>
            <strong>{{ volume.driver }}</strong>
          </div>
          <div class="docker-card-field">
            <span>作用域</span>
            <strong>{{ volume.scope }}</strong>
          </div>
          <div class="docker-card-field">
            <span>引用</span>
            <strong>{{ volume.refCount }}</strong>
          </div>
          <div class="docker-card-field wide">
            <span>挂载点</span>
            <strong :title="volume.mountpoint">{{ volume.mountpoint }}</strong>
          </div>
          <div class="docker-card-field wide">
            <span>创建时间</span>
            <strong>{{ controller.formatTime(volume.createdAt) }}</strong>
          </div>
        </div>

        <template #footer>
          <div class="docker-card-actions">
            <NButton size="tiny" quaternary @click="controller.viewVolumeInspect(volume)">Inspect</NButton>
            <NButton size="tiny" quaternary type="error" @click="controller.confirmRemoveVolume(volume)">删除</NButton>
          </div>
        </template>
      </NCard>
    </div>

    <NModal v-model:show="createVisible" preset="card" title="新建 Docker 存储卷" style="width: min(560px, 92vw)">
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
.docker-theme-dark {
  --docker-card-border: rgba(148, 163, 184, 0.16);
  --docker-card-bg: linear-gradient(145deg, rgba(15, 23, 42, 0.72), rgba(30, 41, 59, 0.46));
  --docker-card-shadow: 0 18px 42px rgba(2, 6, 23, 0.18);
  --docker-card-border-hover: rgba(var(--app-primary-rgb), 0.42);
  --docker-card-bg-hover: linear-gradient(145deg, rgba(15, 23, 42, 0.84), rgba(var(--app-primary-rgb), 0.28));
  --docker-card-field-bg: rgba(15, 23, 42, 0.38);
  --docker-card-label-color: rgba(226, 232, 240, 0.52);
  --docker-card-value-color: rgba(248, 250, 252, 0.9);
}

.docker-theme-light {
  --docker-card-border: rgba(148, 163, 184, 0.22);
  --docker-card-bg: linear-gradient(145deg, rgba(255, 255, 255, 0.96), rgba(241, 245, 249, 0.92));
  --docker-card-shadow: 0 18px 40px rgba(15, 23, 42, 0.08);
  --docker-card-border-hover: rgba(var(--app-primary-rgb), 0.34);
  --docker-card-bg-hover: linear-gradient(145deg, rgba(255, 255, 255, 0.98), rgba(var(--app-primary-rgb), 0.14));
  --docker-card-field-bg: rgba(241, 245, 249, 0.92);
  --docker-card-label-color: rgba(100, 116, 139, 0.9);
  --docker-card-value-color: rgba(30, 41, 59, 0.92);
}

.docker-card-list {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 8px;
  min-height: 0;
  overflow: auto;
  padding-right: 4px;
}

.docker-card {
  flex: none;
  width: 100%;
  border: 1px solid var(--docker-card-border);
  border-radius: 14px;
  background: var(--docker-card-bg);
  box-shadow: var(--docker-card-shadow);
  overflow: hidden;
}

.docker-card:hover {
  border-color: var(--docker-card-border-hover);
  background: var(--docker-card-bg-hover);
}

.docker-card :deep(.docker-card-content) {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.docker-card :deep(.n-card-header) {
  padding: 10px 12px 8px;
}

.docker-card :deep(.n-card__content) {
  padding: 0 12px 8px;
}

.docker-card :deep(.n-card__footer) {
  padding: 6px 12px 10px;
  background: transparent;
}

.docker-card-fields {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
  gap: 7px;
}

.docker-card-field {
  min-width: 0;
  border-radius: 10px;
  background: var(--docker-card-field-bg);
  padding: 6px 8px;
}

.docker-card-field.wide {
  grid-column: auto;
}

.docker-card-field span {
  display: block;
  margin-bottom: 2px;
  color: var(--docker-card-label-color);
  font-size: 11px;
}

.docker-card-field strong {
  display: block;
  overflow: hidden;
  color: var(--docker-card-value-color);
  font-size: 12px;
  font-weight: 500;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.docker-card-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

@media (max-width: 640px) {
  .docker-card-fields {
    grid-template-columns: 1fr;
  }
}
</style>

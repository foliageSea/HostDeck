<script setup lang="ts">
import { reactive, ref } from 'vue'
import { Add } from '@vicons/carbon'
import type { DockerViewController } from '../hooks/useDockerView'
import DockerResourceTable from './DockerResourceTable.vue'
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
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-[12px] overflow-hidden">
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
        <NButton type="primary" @click="openCreateDialog">
          <template #icon>
            <NIcon>
              <Add />
            </NIcon>
          </template>
          新建存储卷
        </NButton>
        <NButton quaternary :loading="controller.loading" @click="controller.refreshVolumes"
          >刷新</NButton
        >
        <NButton quaternary @click="controller.confirmPruneVolumes">清理未使用</NButton>
      </template>

      <template #meta>
        <NTag round size="small"
          >显示 {{ controller.filteredVolumes.length }} / {{ controller.volumes.length }}</NTag
        >
      </template>
    </DockerTabToolbar>

    <NEmpty v-if="controller.filteredVolumes.length === 0" />

    <DockerResourceTable v-else min-width="900px">
      <thead>
        <tr>
          <th style="width: 220px">存储卷</th>
          <th style="width: 110px">驱动</th>
          <th style="width: 100px">作用域</th>
          <th style="width: 100px">引用</th>
          <th>挂载点</th>
          <th style="width: 190px">创建时间</th>
          <th class="docker-table-actions-column" style="width: 130px; text-align: right">操作</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="volume in controller.filteredVolumes" :key="volume.name">
          <td>
            <span class="docker-table-primary" :title="volume.name">{{ volume.name }}</span>
          </td>
          <td>{{ volume.driver }}</td>
          <td>{{ volume.scope }}</td>
          <td>
            <NTag round size="small" :type="volume.refCount > 0 ? 'success' : 'default'">{{
              volume.refCount
            }}</NTag>
          </td>
          <td>
            <span class="docker-table-primary" :title="volume.mountpoint">{{
              volume.mountpoint
            }}</span>
          </td>
          <td class="docker-table-nowrap">{{ controller.formatTime(volume.createdAt) }}</td>
          <td class="docker-table-actions-column">
            <div class="docker-table-actions">
              <NButton size="tiny" quaternary @click="controller.viewVolumeInspect(volume)"
                >检查</NButton
              >
              <NButton
                size="tiny"
                quaternary
                type="error"
                :disabled="volume.refCount > 0"
                @click="controller.confirmRemoveVolume(volume)"
                >删除</NButton
              >
            </div>
          </td>
        </tr>
      </tbody>
    </DockerResourceTable>

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

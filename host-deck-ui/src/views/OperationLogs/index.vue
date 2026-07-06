<script setup lang="ts">
import { computed, h, onMounted, ref } from 'vue'
import { NButton, NDataTable, NTag, type DataTableColumns, type SelectOption } from 'naive-ui'
import { Renew, TrashCan } from '@vicons/carbon'
import { operationLogApi, type OperationLogItem, type OperationLogStatus } from '@/api/operation-log'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'

const settingsStore = useSettingsStore()

const loading = ref(false)
const logs = ref<OperationLogItem[]>([])
const category = ref('')
const status = ref<OperationLogStatus | ''>('')

const categoryOptions: SelectOption[] = [
  { label: '全部模块', value: '' },
  { label: '连接', value: 'auth' },
  { label: '保存主机', value: 'server' },
  { label: '文件', value: 'file' },
  { label: 'Docker', value: 'docker' },
  { label: '端口转发', value: 'portForward' },
  { label: '进程', value: 'process' },
]
const statusOptions: SelectOption[] = [
  { label: '全部状态', value: '' },
  { label: '成功', value: 'success' },
  { label: '失败', value: 'failed' },
]
const categoryLabels: Record<string, string> = {
  auth: '连接',
  docker: 'Docker',
  file: '文件',
  portForward: '端口转发',
  process: '进程',
  server: '保存主机',
}
const actionLabels: Record<string, string> = {
  buildCachePrune: '清理构建缓存',
  chmod: '修改权限',
  composeDown: '停止并移除编排',
  composeRestart: '重启编排',
  composeStop: '停止编排',
  composeUp: '启动编排',
  connect: '连接',
  containerBatchStart: '批量启动容器',
  containerBatchStop: '批量停止容器',
  containerCreate: '创建容器',
  containerPause: '暂停容器',
  containerRecreate: '重建容器',
  containerRemove: '删除容器',
  containerRemoveStopped: '删除已停止容器',
  containerRename: '重命名容器',
  containerRestart: '重启容器',
  containerStart: '启动容器',
  containerStop: '停止容器',
  containerUnpause: '恢复容器',
  copy: '复制',
  create: '创建',
  delete: '删除',
  disconnect: '断开连接',
  extract: '解压',
  imageImport: '导入镜像',
  imagePrune: '清理镜像',
  imagePull: '拉取镜像',
  imageRemove: '删除镜像',
  imageTag: '镜像打标',
  kill: '结束进程',
  mkdir: '新建目录',
  networkConnect: '连接网络',
  networkCreate: '创建网络',
  networkDisconnect: '断开网络',
  networkPrune: '清理网络',
  networkRemove: '删除网络',
  rename: '重命名',
  start: '启动',
  stop: '停止',
  testConnect: '测试连接',
  update: '更新',
  upload: '上传',
  volumeCreate: '创建卷',
  volumePrune: '清理卷',
  volumeRemove: '删除卷',
  write: '写入文件',
}

const filteredSummary = computed(() => `${logs.value.length} 条记录，最多保留最近 1000 条`)
const columns: DataTableColumns<OperationLogItem> = [
  {
    title: '时间',
    key: 'createdAt',
    width: 150,
    render: (row) => formatTime(row.createdAt),
  },
  {
    title: '模块',
    key: 'category',
    width: 110,
    render: (row) => categoryLabels[row.category] ?? row.category,
  },
  {
    title: '操作',
    key: 'action',
    width: 150,
    render: (row) => actionLabels[row.action] ?? row.action,
  },
  {
    title: '目标',
    key: 'target',
    ellipsis: { tooltip: true },
    render: (row) => row.target || '-',
  },
  {
    title: '状态',
    key: 'status',
    width: 90,
    render: (row) =>
      h(
        NTag,
        { size: 'small', type: row.status === 'success' ? 'success' : 'error' },
        { default: () => (row.status === 'success' ? '成功' : '失败') },
      ),
  },
  {
    title: '错误',
    key: 'errorMessage',
    ellipsis: { tooltip: true },
    render: (row) => row.errorMessage || '-',
  },
]

function formatTime(timestamp: number) {
  return new Intl.DateTimeFormat('zh-CN', {
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    month: '2-digit',
    second: '2-digit',
  }).format(new Date(timestamp))
}

async function loadLogs() {
  loading.value = true
  try {
    logs.value = await operationLogApi.list({
      category: category.value || undefined,
      limit: 200,
      status: status.value || undefined,
    })
  } finally {
    loading.value = false
  }
}

function clearLogs() {
  const dialog = getUiApi().dialog.warning({
    title: '清空操作记录',
    content: '确认清空当前全部操作记录？',
    positiveText: '清空',
    negativeText: '取消',
    onPositiveClick: async () => {
      dialog.loading = true
      try {
        await operationLogApi.clear()
        await loadLogs()
      } finally {
        dialog.loading = false
      }
    },
  })
}

onMounted(() => {
  void loadLogs()
})
</script>

<template>
  <div
    class="flex h-full min-h-0 flex-col gap-[14px] p-[18px]"
    :class="settingsStore.isDark ? 'text-[#e2e8f0]' : 'text-[#0f172a]'"
  >
    <div class="flex flex-wrap items-center justify-between gap-[12px]">
      <div>
        <div class="text-[18px] font-700">操作记录</div>
        <div
          class="text-[12px]"
          :class="settingsStore.isDark ? 'text-[rgba(148,163,184,0.94)]' : 'text-[#64748b]'"
        >
          {{ filteredSummary }}
        </div>
      </div>
      <div class="flex flex-wrap items-center gap-[8px]">
        <NSelect
          v-model:value="category"
          class="w-[132px]"
          size="small"
          :options="categoryOptions"
          @update:value="loadLogs"
        />
        <NSelect
          v-model:value="status"
          class="w-[116px]"
          size="small"
          :options="statusOptions"
          @update:value="loadLogs"
        />
        <NButton size="small" secondary :loading="loading" @click="loadLogs">
          <template #icon>
            <NIcon :size="15">
              <Renew />
            </NIcon>
          </template>
          刷新
        </NButton>
        <NButton size="small" tertiary type="error" :disabled="logs.length === 0" @click="clearLogs">
          <template #icon>
            <NIcon :size="15">
              <TrashCan />
            </NIcon>
          </template>
          清空
        </NButton>
      </div>
    </div>

    <NDataTable
      class="min-h-0 flex-1"
      :columns="columns"
      :data="logs"
      :loading="loading"
      :pagination="{ pageSize: 20 }"
      :row-key="(row: OperationLogItem) => row.id"
      flex-height
      size="small"
    />
  </div>
</template>

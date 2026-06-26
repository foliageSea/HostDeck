<script setup lang="ts">
import { computed, h, onMounted, ref } from 'vue'
import { NButton, NTag, type DataTableColumns } from 'naive-ui'
import { processApi, type ProcessInfo } from '@/api/process'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

const settingsStore = useSettingsStore()
const sshStore = useSshStore()

const loading = ref(false)
const killingPid = ref<number | null>(null)
const keyword = ref('')
const processes = ref<ProcessInfo[]>([])
const refreshAt = ref<Date | null>(null)

const hasConnection = computed(() => Boolean(sshStore.connectionId && sshStore.isConnected))
const connectionText = computed(() => {
  if (!hasConnection.value) {
    return '未连接 SSH'
  }

  return `${sshStore.username}@${sshStore.host}:${sshStore.port}`
})
const filteredProcesses = computed(() => {
  const query = keyword.value.trim().toLowerCase()
  if (!query) {
    return processes.value
  }

  return processes.value.filter((process) =>
    [
      String(process.pid),
      process.user,
      process.stat,
      process.start,
      process.time,
      process.command,
    ].some((value) => value.toLowerCase().includes(query)),
  )
})
const totalMemoryMb = computed(() =>
  Math.round(processes.value.reduce((total, process) => total + process.rss, 0) / 1024),
)

const columns: DataTableColumns<ProcessInfo> = [
  {
    title: 'PID',
    key: 'pid',
    width: 96,
    sorter: (left, right) => left.pid - right.pid,
  },
  {
    title: '用户',
    key: 'user',
    width: 130,
    ellipsis: { tooltip: true },
  },
  {
    title: 'CPU',
    key: 'cpu',
    width: 96,
    sorter: (left, right) => left.cpu - right.cpu,
    render: (row) => `${row.cpu.toFixed(1)}%`,
  },
  {
    title: '内存',
    key: 'memory',
    width: 104,
    sorter: (left, right) => left.memory - right.memory,
    render: (row) => `${row.memory.toFixed(1)}%`,
  },
  {
    title: 'RSS',
    key: 'rss',
    width: 116,
    sorter: (left, right) => left.rss - right.rss,
    render: (row) => `${Math.round(row.rss / 1024)} MB`,
  },
  {
    title: '状态',
    key: 'stat',
    width: 96,
    render: (row) => h(NTag, { size: 'small' }, { default: () => row.stat }),
  },
  {
    title: '启动',
    key: 'start',
    width: 108,
  },
  {
    title: '耗时',
    key: 'time',
    width: 112,
  },
  {
    title: '命令',
    key: 'command',
    minWidth: 320,
    ellipsis: { tooltip: true },
  },
  {
    title: '操作',
    key: 'actions',
    width: 92,
    fixed: 'right',
    render: (row) =>
      h(
        NButton,
        {
          disabled: !hasConnection.value,
          loading: killingPid.value === row.pid,
          secondary: true,
          size: 'small',
          type: 'error',
          onClick: () => confirmKill(row),
        },
        { default: () => 'Kill' },
      ),
  },
]

function formatRefreshAt(value: Date | null) {
  if (!value) {
    return '尚未刷新'
  }

  return new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(value)
}

async function fetchProcesses() {
  if (!sshStore.connectionId) {
    getUiApi().message.warning('请先连接 SSH。')
    return
  }

  loading.value = true
  try {
    processes.value = await processApi.list(sshStore.connectionId)
    refreshAt.value = new Date()
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '加载进程列表失败。')
  } finally {
    loading.value = false
  }
}

function confirmKill(process: ProcessInfo) {
  if (!sshStore.connectionId) {
    getUiApi().message.warning('请先连接 SSH。')
    return
  }

  getUiApi().dialog.warning({
    content: `确认结束 PID ${process.pid}？\n${process.command}`,
    negativeText: '取消',
    positiveText: 'Kill',
    title: '结束进程',
    onPositiveClick: async () => {
      killingPid.value = process.pid
      try {
        await processApi.kill(sshStore.connectionId as string, process.pid)
        getUiApi().message.success('进程结束信号已发送。')
        await fetchProcesses()
      } catch (error) {
        getUiApi().message.error(error instanceof Error ? error.message : '结束进程失败。')
      } finally {
        killingPid.value = null
      }
    },
  })
}

onMounted(() => {
  if (hasConnection.value) {
    void fetchProcesses()
  }
})
</script>

<template>
  <div
    class="process-view flex h-full flex-col gap-[16px] overflow-hidden p-[20px]"
    :class="
      settingsStore.isDark
        ? 'bg-[radial-gradient(circle_at_top_left,rgba(34,197,94,0.12),transparent_32%),rgba(15,23,42,0.05)]'
        : 'bg-[radial-gradient(circle_at_top_left,rgba(34,197,94,0.16),transparent_32%),rgba(248,250,252,0.62)]'
    "
  >
    <div class="flex flex-wrap items-start justify-between gap-[12px]">
      <div>
        <div class="text-[24px] font-700 leading-tight">进程管理</div>
      </div>
      <NSpace>
        <NInput
          v-model:value="keyword"
          clearable
          class="w-[260px] lt-md:w-full"
          placeholder="搜索 PID / 用户 / 命令"
        />
        <NButton secondary :loading="loading" :disabled="!hasConnection" @click="fetchProcesses">
          刷新
        </NButton>
      </NSpace>
    </div>

    <div class="grid grid-cols-4 gap-[12px] lt-lg:grid-cols-2 lt-md:grid-cols-1">
      <NCard size="small">
        <div class="text-[12px] text-[rgba(100,116,139,0.86)]">当前连接</div>
        <div class="mt-[8px] flex items-center gap-[8px] text-[15px] font-600">
          <NTag :type="hasConnection ? 'success' : 'warning'" size="small">
            {{ hasConnection ? '已连接' : '未连接' }}
          </NTag>
          <span class="truncate">{{ connectionText }}</span>
        </div>
      </NCard>
      <NCard size="small">
        <div class="text-[12px] text-[rgba(100,116,139,0.86)]">进程数</div>
        <div class="mt-[8px] text-[26px] font-700">{{ processes.length }}</div>
      </NCard>
      <NCard size="small">
        <div class="text-[12px] text-[rgba(100,116,139,0.86)]">RSS 合计</div>
        <div class="mt-[8px] text-[26px] font-700 text-[#22c55e]">{{ totalMemoryMb }} MB</div>
      </NCard>
      <NCard size="small">
        <div class="text-[12px] text-[rgba(100,116,139,0.86)]">最近刷新</div>
        <div class="mt-[12px] text-[15px] font-600">{{ formatRefreshAt(refreshAt) }}</div>
      </NCard>
    </div>

    <NCard class="min-h-0 flex-1" content-style="height: 100%; padding: 0;" :bordered="false">
      <NDataTable
        class="h-full"
        :bordered="false"
        :single-line="false"
        :columns="columns"
        :data="filteredProcesses"
        :loading="loading"
        :pagination="{ pageSize: 15, showSizePicker: true, pageSizes: [15, 30, 50, 100] }"
        flex-height
      />
    </NCard>
  </div>
</template>

<style scoped>
.process-view :deep(.n-data-table) {
  height: 100%;
}
</style>

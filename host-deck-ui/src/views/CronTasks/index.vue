<script setup lang="ts">
import { computed, h, onMounted, reactive, ref } from 'vue'
import { Plus, RefreshCw } from '@lucide/vue'
import { NButton, NDataTable, NTag, type DataTableColumns } from 'naive-ui'
import { cronTaskApi, type CronExecutionHistory, type CronTask, type CronTaskPayload } from '@/api/cron-task'
import { getUiApi } from '@/lib/ui'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

const settingsStore = useSettingsStore()
const sshStore = useSshStore()
const tasks = ref<CronTask[]>([])
const history = ref<CronExecutionHistory[]>([])
const loading = ref(false)
const saving = ref(false)
const operatingId = ref<number | null>(null)
const editorVisible = ref(false)
const historyVisible = ref(false)
const editingId = ref<number | null>(null)
const activeTask = ref<CronTask | null>(null)
const form = reactive({ name: '', schedule: '0 2 * * *', command: '', enabled: true, templateType: null as CronTask['templateType'] })

const connected = computed(() => Boolean(sshStore.isConnected && sshStore.connectionId))
const connectionId = computed(() => sshStore.connectionId ?? '')

const templates = {
  backup: {
    name: '目录备份', schedule: '0 2 * * *',
    command: "mkdir -p /var/backups && tar -czf /var/backups/backup-$(date +%Y%m%d-%H%M%S).tar.gz /path/to/source && find /var/backups -type f -name '*.tar.gz' -mtime +14 -delete",
  },
  cleanup: {
    name: '过期文件清理', schedule: '30 3 * * *',
    command: "find /path/to/cleanup -type f -mtime +30 -delete",
  },
  'health-check': {
    name: '磁盘健康检查', schedule: '*/15 * * * *',
    command: "df -P / | awk 'NR == 2 { sub(/%/, \"\", $5); exit $5 >= 90 }'",
  },
} as const

function resetForm() {
  editingId.value = null
  form.name = ''
  form.schedule = '0 2 * * *'
  form.command = ''
  form.enabled = true
  form.templateType = null
}

function applyTemplate(type: keyof typeof templates) {
  const template = templates[type]
  form.name = template.name
  form.schedule = template.schedule
  form.command = template.command
  form.templateType = type
}

function openCreate() {
  resetForm()
  editorVisible.value = true
}

function openEdit(task: CronTask) {
  editingId.value = task.id
  form.name = task.name
  form.schedule = task.schedule
  form.command = task.command
  form.enabled = task.enabled
  form.templateType = task.templateType
  editorVisible.value = true
}

function payload(): CronTaskPayload {
  return {
    connectionId: connectionId.value,
    name: form.name.trim(),
    schedule: form.schedule.trim(),
    command: form.command.trim(),
    enabled: form.enabled,
    templateType: form.templateType,
  }
}

function upsert(task: CronTask) {
  const index = tasks.value.findIndex((item) => item.id === task.id)
  if (index < 0) tasks.value.unshift(task)
  else tasks.value[index] = task
}

async function loadTasks() {
  if (!connected.value) return
  loading.value = true
  try {
    tasks.value = await cronTaskApi.list(connectionId.value)
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '加载定时任务失败。')
  } finally {
    loading.value = false
  }
}

async function saveTask() {
  if (!form.name.trim() || !form.schedule.trim() || !form.command.trim()) {
    getUiApi().message.warning('请填写任务名称、计划和命令。')
    return
  }
  saving.value = true
  try {
    const next = editingId.value === null
      ? await cronTaskApi.create(payload())
      : await cronTaskApi.update(editingId.value, payload())
    upsert(next)
    editorVisible.value = false
    getUiApi().message.success('定时任务已保存。')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '保存定时任务失败。')
  } finally {
    saving.value = false
  }
}

async function runTask(task: CronTask) {
  operatingId.value = task.id
  try {
    const result = await cronTaskApi.run(task.id, connectionId.value)
    getUiApi().message[result.status === 'success' ? 'success' : 'error'](
      result.status === 'success' ? '任务执行成功。' : '任务执行失败，请查看历史记录。',
    )
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '任务执行失败。')
  } finally {
    operatingId.value = null
  }
}

function removeTask(task: CronTask) {
  getUiApi().dialog.warning({
    title: '删除定时任务', content: `将从远端 crontab 移除“${task.name}”。`, positiveText: '删除', negativeText: '取消',
    onPositiveClick: async () => {
      operatingId.value = task.id
      try {
        await cronTaskApi.delete(task.id, connectionId.value)
        tasks.value = tasks.value.filter((item) => item.id !== task.id)
      } catch (error) {
        getUiApi().message.error(error instanceof Error ? error.message : '删除定时任务失败。')
      } finally {
        operatingId.value = null
      }
    },
  })
}

async function openHistory(task: CronTask) {
  activeTask.value = task
  historyVisible.value = true
  await refreshHistory()
}

async function refreshHistory() {
  const task = activeTask.value
  if (!task) return
  operatingId.value = task.id
  try {
    await cronTaskApi.syncHistory(task.id, connectionId.value)
    history.value = await cronTaskApi.history(task.id, connectionId.value)
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '同步执行历史失败。')
  } finally {
    operatingId.value = null
  }
}

function formatTime(value?: number | null) {
  return value ? new Intl.DateTimeFormat('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(new Date(value)) : '-'
}

function formatDuration(value?: number | null) {
  if (value === null || value === undefined) return '-'
  return value < 1000 ? `${value} ms` : `${(value / 1000).toFixed(1)} s`
}

const taskColumns: DataTableColumns<CronTask> = [
  { title: '任务', key: 'name', minWidth: 160, render: (row) => h('div', [h('div', { class: 'font-600' }, row.name), h('div', { class: 'mt-1 truncate text-[12px] opacity-60' }, row.command)]) },
  { title: '计划', key: 'schedule', width: 130, render: (row) => h('code', row.schedule) },
  { title: '状态', key: 'enabled', width: 90, render: (row) => h(NTag, { size: 'small', type: row.enabled ? 'success' : 'default' }, { default: () => row.enabled ? '已启用' : '已停用' }) },
  { title: '操作', key: 'actions', width: 250, render: (row) => h('div', { class: 'flex gap-1' }, [
    h(NButton, { size: 'tiny', secondary: true, loading: operatingId.value === row.id, onClick: () => void runTask(row) }, { default: () => '执行' }),
    h(NButton, { size: 'tiny', secondary: true, onClick: () => void openHistory(row) }, { default: () => '历史' }),
    h(NButton, { size: 'tiny', secondary: true, onClick: () => openEdit(row) }, { default: () => '编辑' }),
    h(NButton, { size: 'tiny', secondary: true, type: 'error', onClick: () => removeTask(row) }, { default: () => '删除' }),
  ]) },
]

onMounted(() => void loadTasks())
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-[14px] p-[18px]" :class="settingsStore.isDark ? 'text-[#e2e8f0]' : 'text-[#0f172a]'">
    <div class="flex flex-wrap items-center justify-between gap-[12px]">
      <div><div class="text-[18px] font-700">定时任务</div><div class="mt-1 text-[12px] opacity-60">管理 HostDeck 托管的远端 crontab 与执行历史</div></div>
      <div class="flex gap-2"><NButton size="small" secondary :loading="loading" :disabled="!connected" @click="loadTasks"><RefreshCw :size="15" /></NButton><NButton size="small" type="primary" :disabled="!connected" @click="openCreate"><template #icon><Plus :size="16" /></template>新增任务</NButton></div>
    </div>
    <NAlert v-if="!connected" type="warning" :show-icon="true">请先建立 SSH 连接。</NAlert>
    <div class="grid grid-cols-3 gap-2 lt-md:grid-cols-1">
      <NButton secondary @click="openCreate(); applyTemplate('backup')">快速创建备份</NButton>
      <NButton secondary @click="openCreate(); applyTemplate('cleanup')">快速创建清理</NButton>
      <NButton secondary @click="openCreate(); applyTemplate('health-check')">快速创建健康检查</NButton>
    </div>
    <NDataTable class="min-h-0 flex-1" :columns="taskColumns" :data="tasks" :loading="loading" :pagination="{ pageSize: 12 }" :row-key="(row: CronTask) => row.id" flex-height size="small" />

    <NModal v-model:show="editorVisible" preset="card" :title="editingId === null ? '新增定时任务' : '编辑定时任务'" style="width: min(680px, calc(100vw - 32px))">
      <NForm label-placement="top"><NFormItem label="任务名称"><NInput v-model:value="form.name" /></NFormItem><div class="grid grid-cols-2 gap-3 lt-sm:grid-cols-1"><NFormItem label="Cron 计划"><NInput v-model:value="form.schedule" placeholder="0 2 * * *" /></NFormItem><NFormItem label="启用"><NSwitch v-model:value="form.enabled" /></NFormItem></div><NFormItem label="命令"><NInput v-model:value="form.command" type="textarea" :autosize="{ minRows: 4, maxRows: 8 }" /></NFormItem></NForm>
      <template #footer><div class="flex justify-end gap-2"><NButton @click="editorVisible = false">取消</NButton><NButton type="primary" :loading="saving" @click="saveTask">保存</NButton></div></template>
    </NModal>

    <NDrawer v-model:show="historyVisible" width="min(760px, calc(100vw - 24px))" placement="right"><NDrawerContent :title="`${activeTask?.name ?? ''} · 执行历史`" closable><template #header-extra><NButton size="small" secondary :loading="operatingId === activeTask?.id" @click="refreshHistory"><RefreshCw :size="15" /></NButton></template><NDataTable :data="history" :pagination="{ pageSize: 10 }" :row-key="(row: CronExecutionHistory) => row.id" size="small" :columns="[{ title: '时间', key: 'startedAt', render: (row: CronExecutionHistory) => formatTime(row.startedAt) }, { title: '触发', key: 'triggerType', render: (row: CronExecutionHistory) => row.triggerType === 'manual' ? '手动' : '计划' }, { title: '结果', key: 'status', render: (row: CronExecutionHistory) => row.status === 'success' ? '成功' : '失败' }, { title: '退出码', key: 'exitCode' }, { title: '耗时', key: 'durationMs', render: (row: CronExecutionHistory) => formatDuration(row.durationMs) }]" /><div v-for="item in history" :key="`output-${item.id}`" class="mt-3"><NTag :type="item.status === 'success' ? 'success' : 'error'" size="small">{{ formatTime(item.startedAt) }}</NTag><pre v-if="item.stdout || item.stderr" class="mt-2 max-h-[180px] overflow-auto whitespace-pre-wrap break-words rounded bg-[rgba(148,163,184,0.12)] p-2 text-[12px]">{{ item.stdout }}{{ item.stderr ? `\n${item.stderr}` : '' }}</pre></div></NDrawerContent></NDrawer>
  </div>
</template>

<script setup lang="ts">
import { computed, h, onMounted, ref, watch } from 'vue'
import type { DataTableColumns } from 'naive-ui'
import { NButton, NIcon, NPopover, NSpace } from 'naive-ui'
import {
  Add,
  Catalog,
  Copy,
  Cube,
  Download,
  Edit,
  Information,
  Launch,
  List,
  Pause,
  PlayFilledAlt,
  Restart,
  StopFilledAlt,
  TrashCan,
  Upload,
} from '@vicons/carbon'
import {
  dockerApi,
  type DockerContainer,
  type DockerContainerDiagnostic,
  type DockerContainerInspect,
  type DockerContainerStats,
  type DockerCreateContainerPayload,
  type DockerImageContainerRef,
  type DockerImageHistoryItem,
  type DockerImage,
} from '@/api/docker'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useSshStore } from '@/stores/ssh'

const sshStore = useSshStore()
const desktopStore = useDesktopStore()

const activeTab = ref<'containers' | 'images'>('containers')
const loading = ref(false)
const dockerAvailable = ref<boolean | null>(null)
const containers = ref<DockerContainer[]>([])
const containerStatusFilter = ref<'all' | 'running' | 'stopped' | 'paused' | 'restarting' | 'exited'>('all')
const images = ref<DockerImage[]>([])
const statsMap = ref<Record<string, DockerContainerStats>>({})
const diagnosticsMap = ref<Record<string, DockerContainerDiagnostic>>({})
const selectedContainerIds = ref<string[]>([])
const batchProcessing = ref(false)
const logsVisible = ref(false)
const logsLoading = ref(false)
const logsRefreshing = ref(false)
const logsTitle = ref('')
const logsContent = ref('')
const logsTail = ref(200)
const logsAutoRefresh = ref(false)
const logsKeyword = ref('')
const logsLastUpdatedAt = ref<Date | null>(null)
const logsContainerName = ref('')
const inspectVisible = ref(false)
const inspectLoading = ref(false)
const inspectTitle = ref('')
const inspectContent = ref<DockerContainerInspect | null>(null)
const pullingImage = ref(false)
const pullImageName = ref('')
const createVisible = ref(false)
const creatingContainer = ref(false)
const createForm = ref<DockerCreateContainerPayload>({
  image: '',
  name: '',
  restartPolicy: 'no',
  start: true,
})
const createPortsText = ref('')
const createEnvText = ref('')
const createVolumesText = ref('')
const createCmdText = ref('')
const createEntrypointText = ref('')
const imageTagVisible = ref(false)
const imageTagging = ref(false)
const imageTagSource = ref('')
const imageTagTarget = ref('')
const imageHistoryVisible = ref(false)
const imageHistoryLoading = ref(false)
const imageHistoryTitle = ref('')
const imageHistoryItems = ref<DockerImageHistoryItem[]>([])
const imageRefsVisible = ref(false)
const imageRefsLoading = ref(false)
const imageRefsTitle = ref('')
const imageRefsItems = ref<DockerImageContainerRef[]>([])
const renameVisible = ref(false)
const renamingContainer = ref(false)
const renamingContainerId = ref('')
const renamingContainerName = ref('')
let logsRefreshTimer: number | null = null

const runningContainers = computed(() => containers.value.filter((item) => item.state === 'running').length)
const stoppedContainers = computed(() => containers.value.filter((item) => item.state !== 'running').length)
const danglingImages = computed(() => images.value.filter((item) => item.dangling).length)
const containerStatusOptions = [
  { label: '全部状态', value: 'all' },
  { label: '运行中', value: 'running' },
  { label: '已停止', value: 'stopped' },
  { label: '已暂停', value: 'paused' },
  { label: '重启中', value: 'restarting' },
  { label: '已退出', value: 'exited' },
]
const filteredContainers = computed(() =>
  containers.value.filter((item) => {
    const status = item.status.toLowerCase()

    if (containerStatusFilter.value === 'all') {
      return true
    }

    if (containerStatusFilter.value === 'running') {
      return item.state === 'running' && !status.includes('paused')
    }

    if (containerStatusFilter.value === 'stopped') {
      return item.state !== 'running'
    }

    if (containerStatusFilter.value === 'paused') {
      return status.includes('paused')
    }

    if (containerStatusFilter.value === 'restarting') {
      return item.state === 'restarting' || status.includes('restarting')
    }

    return item.state === 'exited' || status.includes('exited')
  }),
)
const containerPagination = { pageSize: 8 }
const imagePagination = { pageSize: 8 }
const selectedStoppedIds = computed(() =>
  containers.value.filter((item) => selectedContainerIds.value.includes(item.id) && item.state !== 'running').map((item) => item.id),
)
const selectedRunningIds = computed(() =>
  containers.value.filter((item) => selectedContainerIds.value.includes(item.id) && item.state === 'running').map((item) => item.id),
)
const displayedLogs = computed(() => {
  if (!logsKeyword.value.trim()) {
    return logsContent.value
  }

  const keyword = logsKeyword.value.trim().toLowerCase()
  return logsContent.value
    .split(/\r?\n/)
    .filter((line) => line.toLowerCase().includes(keyword))
    .join('\n')
})

function renderContainerPorts(row: DockerContainer) {
  const ports = row.ports ?? []

  if (ports.length === 0) {
    return '-'
  }

  if (ports.length === 1) {
    return h('span', { class: 'container-port-summary', title: ports[0] }, ports[0])
  }

  return h(
    NSpace,
    { align: 'center', size: 6, wrap: false },
    {
      default: () => [
        h('span', { class: 'container-port-summary', title: ports.join(', ') }, `${ports[0]} 等 ${ports.length} 项`),
        h(
          NPopover,
          { trigger: 'click', placement: 'bottom-start' },
          {
            trigger: () => h(NButton, { size: 'tiny', quaternary: true }, { default: () => '查看详情' }),
            default: () => h('div', { class: 'container-port-popover' }, ports.map((port) => h('div', { class: 'container-port-item' }, port))),
          },
        ),
      ],
    },
  )
}

function renderContainerActions(row: DockerContainer) {
  const paused = row.status.toLowerCase().includes('paused')

  return h(
    NPopover,
    { trigger: 'click', placement: 'bottom-end' },
    {
      trigger: () => h(NButton, { size: 'small', quaternary: true }, { default: () => '查看详情' }),
      default: () =>
        h(NSpace, { class: 'container-action-popover', wrap: true, size: 4 }, () => [
          row.state === 'running'
            ? h(
                NButton,
                { size: 'small', quaternary: true, onClick: () => confirmContainerAction(row, 'stop') },
                { icon: () => h(NIcon, null, { default: () => h(StopFilledAlt) }), default: () => '停止' },
              )
            : h(
                NButton,
                { size: 'small', quaternary: true, onClick: () => confirmContainerAction(row, 'start') },
                { icon: () => h(NIcon, null, { default: () => h(PlayFilledAlt) }), default: () => '启动' },
              ),
          h(
            NButton,
            { size: 'small', quaternary: true, onClick: () => confirmContainerAction(row, 'restart') },
            { icon: () => h(NIcon, null, { default: () => h(Restart) }), default: () => '重启' },
          ),
          h(
            NButton,
            {
              size: 'small',
              quaternary: true,
              disabled: row.state !== 'running',
              onClick: () => handleContainerAdvancedAction(row, paused ? 'unpause' : 'pause'),
            },
            {
              icon: () => h(NIcon, null, { default: () => h(Pause) }),
              default: () => (paused ? '恢复' : '暂停'),
            },
          ),
          h(
            NButton,
            { size: 'small', quaternary: true, onClick: () => viewLogs(row) },
            { icon: () => h(NIcon, null, { default: () => h(Catalog) }), default: () => '日志' },
          ),
          h(
            NButton,
            { size: 'small', quaternary: true, onClick: () => viewInspect(row) },
            { icon: () => h(NIcon, null, { default: () => h(Information) }), default: () => 'Inspect' },
          ),
          h(
            NButton,
            { size: 'small', quaternary: true, onClick: () => openRenameDialog(row) },
            { icon: () => h(NIcon, null, { default: () => h(Edit) }), default: () => '重命名' },
          ),
          h(
            NButton,
            { size: 'small', quaternary: true, onClick: () => recreateContainer(row) },
            { icon: () => h(NIcon, null, { default: () => h(Restart) }), default: () => '重建' },
          ),
          h(
            NButton,
            {
              size: 'small',
              quaternary: true,
              disabled: row.state !== 'running',
              onClick: () => enterShell(row),
            },
            { icon: () => h(NIcon, null, { default: () => h(Launch) }), default: () => 'Shell' },
          ),
          h(
            NButton,
            { size: 'small', quaternary: true, type: 'error', onClick: () => confirmContainerAction(row, 'remove') },
            { icon: () => h(NIcon, null, { default: () => h(TrashCan) }), default: () => '删除' },
          ),
        ]),
    },
  )
}

const containerColumns: DataTableColumns<DockerContainer> = [
  { type: 'selection', width: 48 },
  { title: '名称', key: 'name' },
  { title: '镜像', key: 'image' },
  { title: '状态', key: 'status' },
  {
    title: '资源',
    key: 'stats',
    render: (row) => {
      const stats = statsMap.value[row.id]
      const diagnostics = diagnosticsMap.value[row.id]
      return stats
        ? `${stats.cpuPercent} CPU / ${stats.memUsage}${diagnostics ? ` / 重启 ${diagnostics.restartCount}` : ''}`
        : '-'
    },
  },
  { title: '端口', key: 'ports', width: 220, render: renderContainerPorts },
  { title: '创建时间', key: 'createdAt', render: (row) => formatTime(row.createdAt) },
  {
    title: '操作',
    key: 'actions',
    width: 108,
    render: renderContainerActions,
  },
]

const imageColumns: DataTableColumns<DockerImage> = [
  { title: '仓库', key: 'repository' },
  { title: '标签', key: 'tag' },
  { title: '大小', key: 'size' },
  { title: '创建时间', key: 'createdAt', render: (row) => formatTime(row.createdAt) },
  { title: '状态', key: 'dangling', render: (row) => (row.dangling ? '悬空' : row.inUse ? '使用中' : '普通') },
  {
    title: '操作',
    key: 'actions',
    width: 260,
    render: (row) =>
      h(NSpace, { wrap: true, size: 4 }, () => [
        h(
          NButton,
          { size: 'small', quaternary: true, onClick: () => openImageTagDialog(row) },
          { icon: () => h(NIcon, null, { default: () => h(Edit) }), default: () => 'Tag' },
        ),
        h(
          NButton,
          { size: 'small', quaternary: true, onClick: () => viewImageHistory(row) },
          { icon: () => h(NIcon, null, { default: () => h(List) }), default: () => '历史' },
        ),
        h(
          NButton,
          { size: 'small', quaternary: true, onClick: () => viewImageRefs(row) },
          { icon: () => h(NIcon, null, { default: () => h(Information) }), default: () => '引用' },
        ),
        h(
          NButton,
          { size: 'small', quaternary: true, type: 'error', onClick: () => confirmRemoveImage(row) },
          { icon: () => h(NIcon, null, { default: () => h(TrashCan) }), default: () => '删除' },
        ),
      ]),
  },
]

function requireSession() {
  if (!sshStore.sessionId) {
    throw new Error('当前没有可用的 SSH 会话。')
  }

  return sshStore.sessionId
}

function formatTime(value?: string) {
  if (!value) {
    return '-'
  }

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return value
  }

  return date.toLocaleString('zh-CN')
}

function toLineList(value: string) {
  return value
    .split(/\r?\n/)
    .map((item) => item.trim())
    .filter(Boolean)
}

function formatDateTime(value: Date | null) {
  if (!value) {
    return '-'
  }

  return value.toLocaleString('zh-CN')
}

function containerRowKey(row: DockerContainer) {
  return row.id
}

async function copyLogs() {
  try {
    await navigator.clipboard.writeText(displayedLogs.value)
    getUiApi().message.success('日志已复制到剪贴板。')
  } catch (error) {
    console.error('Failed to copy logs', error)
    getUiApi().message.error('复制日志失败。')
  }
}

function downloadLogs() {
  const text = displayedLogs.value
  const filename = `${logsContainerName.value || 'container'}-${Date.now()}.log`
  const blob = new Blob([text], { type: 'text/plain;charset=utf-8' })
  const url = window.URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = filename
  anchor.click()
  window.URL.revokeObjectURL(url)
}

async function refreshLogs(silent = false) {
  if (!logsContainerName.value) {
    return
  }

  try {
    const container = containers.value.find((item) => item.name === logsContainerName.value)
    if (!container) {
      return
    }

    if (silent) {
      logsRefreshing.value = true
    } else {
      logsLoading.value = true
    }

    const sessionId = requireSession()
    const result = await dockerApi.getContainerLogsAdvanced(sessionId, container.id, {
      tail: logsTail.value,
      timestamps: true,
    })
    logsContent.value = result.logs
    logsLastUpdatedAt.value = new Date()
  } catch (error) {
    console.error('Failed to refresh logs', error)
    if (!silent) {
      logsContent.value = error instanceof Error ? error.message : '日志加载失败。'
    }
  } finally {
    logsLoading.value = false
    logsRefreshing.value = false
  }
}

function syncLogsRefreshTimer() {
  if (logsRefreshTimer) {
    clearInterval(logsRefreshTimer)
    logsRefreshTimer = null
  }

  if (logsVisible.value && logsAutoRefresh.value) {
    logsRefreshTimer = window.setInterval(() => {
      void refreshLogs(true)
    }, 4000)
  }
}

async function refreshContainerStats() {
  if (!containers.value.length) {
    statsMap.value = {}
    return
  }

  try {
    const sessionId = requireSession()
    const nextEntries = await Promise.all(
      containers.value.map(async (container) => {
        try {
          const stats = await dockerApi.getContainerStats(sessionId, container.id)
          return [container.id, stats] as const
        } catch {
          return null
        }
      }),
    )

    statsMap.value = Object.fromEntries(nextEntries.filter((item): item is readonly [string, DockerContainerStats] => item !== null))
  } catch (error) {
    console.error('Failed to refresh container stats', error)
  }
}

async function refreshContainerDiagnostics() {
  if (!containers.value.length) {
    diagnosticsMap.value = {}
    return
  }

  try {
    const sessionId = requireSession()
    const diagnostics = await dockerApi.getContainerDiagnostics(
      sessionId,
      containers.value.map((container) => container.id),
    )
    diagnosticsMap.value = Object.fromEntries(diagnostics.map((item) => [item.containerId, item]))
  } catch (error) {
    console.error('Failed to refresh container diagnostics', error)
  }
}

async function loadDockerState() {
  loading.value = true

  try {
    const sessionId = requireSession()
    const result = await dockerApi.checkDocker(sessionId)
    dockerAvailable.value = result.available

    if (!result.available) {
      containers.value = []
      images.value = []
      return
    }

    const [nextContainers, nextImages] = await Promise.all([
      dockerApi.listContainers(sessionId),
      dockerApi.listImages(sessionId),
    ])

    containers.value = nextContainers
    images.value = nextImages
    selectedContainerIds.value = selectedContainerIds.value.filter((id) =>
      nextContainers.some((container) => container.id === id),
    )
    await refreshContainerStats()
    await refreshContainerDiagnostics()
  } catch (error) {
    console.error('Failed to load Docker state', error)
    dockerAvailable.value = false
    getUiApi().message.error(error instanceof Error ? error.message : '加载 Docker 数据失败。')
  } finally {
    loading.value = false
  }
}

async function refresh() {
  await loadDockerState()
}

async function handleContainerAction(
  container: DockerContainer,
  action: 'start' | 'stop' | 'restart' | 'remove',
) {
  try {
    const sessionId = requireSession()

    if (action === 'start') {
      await dockerApi.startContainer(sessionId, container.id)
      getUiApi().message.success(`已启动容器 ${container.name}。`)
    }

    if (action === 'stop') {
      await dockerApi.stopContainer(sessionId, container.id)
      getUiApi().message.success(`已停止容器 ${container.name}。`)
    }

    if (action === 'restart') {
      await dockerApi.restartContainer(sessionId, container.id)
      getUiApi().message.success(`已重启容器 ${container.name}。`)
    }

    if (action === 'remove') {
      await dockerApi.removeContainer(sessionId, container.id, true)
      getUiApi().message.success(`已删除容器 ${container.name}。`)
    }

    await loadDockerState()
  } catch (error) {
    console.error(`Failed to ${action} container`, error)
    getUiApi().message.error(error instanceof Error ? error.message : '容器操作失败。')
  }
}

async function handleContainerAdvancedAction(container: DockerContainer, action: 'pause' | 'unpause') {
  try {
    const sessionId = requireSession()

    if (action === 'pause') {
      await dockerApi.pauseContainer(sessionId, container.id)
      getUiApi().message.success(`已暂停容器 ${container.name}。`)
    }

    if (action === 'unpause') {
      await dockerApi.unpauseContainer(sessionId, container.id)
      getUiApi().message.success(`已恢复容器 ${container.name}。`)
    }

    await loadDockerState()
  } catch (error) {
    console.error(`Failed to ${action} container`, error)
    getUiApi().message.error(error instanceof Error ? error.message : '容器高级操作失败。')
  }
}

function confirmContainerAction(container: DockerContainer, action: 'start' | 'stop' | 'restart' | 'remove') {
  const actionTextMap = {
    remove: '删除',
    restart: '重启',
    start: '启动',
    stop: '停止',
  } as const

  getUiApi().dialog.warning({
    title: `${actionTextMap[action]}容器`,
    content: `确认${actionTextMap[action]}容器 ${container.name}？`,
    positiveText: actionTextMap[action],
    negativeText: '取消',
    onPositiveClick: () => handleContainerAction(container, action),
  })
}

async function viewLogs(container: DockerContainer) {
  logsVisible.value = true
  logsTitle.value = `容器日志 · ${container.name}`
  logsContainerName.value = container.name
  logsKeyword.value = ''
  logsLastUpdatedAt.value = null
  await refreshLogs()
}

async function viewInspect(container: DockerContainer) {
  inspectVisible.value = true
  inspectLoading.value = true
  inspectTitle.value = `Inspect · ${container.name}`
  inspectContent.value = null

  try {
    const sessionId = requireSession()
    inspectContent.value = await dockerApi.inspectContainer(sessionId, container.id)
  } catch (error) {
    console.error('Failed to inspect container', error)
    getUiApi().message.error(error instanceof Error ? error.message : 'Inspect 加载失败。')
  } finally {
    inspectLoading.value = false
  }
}

async function enterShell(container: DockerContainer) {
  if (container.state !== 'running') {
    getUiApi().message.error('容器未运行，无法进入 Shell。')
    return
  }

  try {
    const sessionId = requireSession()
    const result = await dockerApi.createContainerShellSession(sessionId, container.id)
    desktopStore.openWindow('terminal', {
      sessionId: result.sessionId,
      title: `Shell · ${container.name}`,
    })
  } catch (error) {
    console.error('Failed to enter container shell', error)
    getUiApi().message.error(error instanceof Error ? error.message : '进入容器 Shell 失败。')
  }
}

function openRenameDialog(container: DockerContainer) {
  renamingContainerId.value = container.id
  renamingContainerName.value = container.name
  renameVisible.value = true
}

async function submitRenameContainer() {
  if (!renamingContainerId.value || !renamingContainerName.value.trim()) {
    getUiApi().message.error('请输入新的容器名称。')
    return
  }

  renamingContainer.value = true
  try {
    const sessionId = requireSession()
    await dockerApi.renameContainer(sessionId, renamingContainerId.value, renamingContainerName.value.trim())
    renameVisible.value = false
    getUiApi().message.success('容器重命名成功。')
    await loadDockerState()
  } catch (error) {
    console.error('Failed to rename container', error)
    getUiApi().message.error(error instanceof Error ? error.message : '容器重命名失败。')
  } finally {
    renamingContainer.value = false
  }
}

async function recreateContainer(container: DockerContainer) {
  try {
    const sessionId = requireSession()
    const result = await dockerApi.recreateContainer(sessionId, container.id)
    getUiApi().message.success(`容器 ${result.name} 重建完成。`)
    await loadDockerState()
  } catch (error) {
    console.error('Failed to recreate container', error)
    getUiApi().message.error(error instanceof Error ? error.message : '容器重建失败。')
  }
}

async function removeImage(image: DockerImage) {
  try {
    const sessionId = requireSession()
    await dockerApi.removeImage(sessionId, image.id, true)
    getUiApi().message.success(`已删除镜像 ${image.repository}:${image.tag}。`)
    await loadDockerState()
  } catch (error) {
    console.error('Failed to remove image', error)
    getUiApi().message.error(error instanceof Error ? error.message : '删除镜像失败。')
  }
}

function openImageTagDialog(image: DockerImage) {
  imageTagSource.value = `${image.repository}:${image.tag}`
  imageTagTarget.value = ''
  imageTagVisible.value = true
}

async function submitTagImage() {
  if (!imageTagSource.value.trim() || !imageTagTarget.value.trim()) {
    getUiApi().message.error('源镜像和目标标签都不能为空。')
    return
  }

  imageTagging.value = true
  try {
    const sessionId = requireSession()
    await dockerApi.tagImage(sessionId, imageTagSource.value.trim(), imageTagTarget.value.trim())
    imageTagVisible.value = false
    getUiApi().message.success('镜像重新打标签成功。')
    await loadDockerState()
  } catch (error) {
    console.error('Failed to tag image', error)
    getUiApi().message.error(error instanceof Error ? error.message : '镜像重新打标签失败。')
  } finally {
    imageTagging.value = false
  }
}

async function viewImageHistory(image: DockerImage) {
  imageHistoryVisible.value = true
  imageHistoryLoading.value = true
  imageHistoryTitle.value = `镜像历史 · ${image.repository}:${image.tag}`
  imageHistoryItems.value = []

  try {
    const sessionId = requireSession()
    imageHistoryItems.value = await dockerApi.getImageHistory(sessionId, image.id)
  } catch (error) {
    console.error('Failed to load image history', error)
    getUiApi().message.error(error instanceof Error ? error.message : '获取镜像历史失败。')
  } finally {
    imageHistoryLoading.value = false
  }
}

async function viewImageRefs(image: DockerImage) {
  imageRefsVisible.value = true
  imageRefsLoading.value = true
  imageRefsTitle.value = `引用容器 · ${image.repository}:${image.tag}`
  imageRefsItems.value = []

  try {
    const sessionId = requireSession()
    imageRefsItems.value = await dockerApi.getImageContainers(sessionId, image.id)
  } catch (error) {
    console.error('Failed to load image refs', error)
    getUiApi().message.error(error instanceof Error ? error.message : '获取镜像引用容器失败。')
  } finally {
    imageRefsLoading.value = false
  }
}

function confirmRemoveImage(image: DockerImage) {
  getUiApi().dialog.warning({
    title: '删除镜像',
    content: `确认删除镜像 ${image.repository}:${image.tag}？`,
    positiveText: '删除',
    negativeText: '取消',
    onPositiveClick: () => removeImage(image),
  })
}

async function pullImage() {
  if (!pullImageName.value.trim()) {
    return
  }

  pullingImage.value = true
  try {
    const sessionId = requireSession()
    await dockerApi.pullImage(sessionId, pullImageName.value.trim())
    getUiApi().message.success(`已开始拉取镜像 ${pullImageName.value.trim()}。`)
    pullImageName.value = ''
    await loadDockerState()
  } catch (error) {
    console.error('Failed to pull image', error)
    getUiApi().message.error(error instanceof Error ? error.message : '拉取镜像失败。')
  } finally {
    pullingImage.value = false
  }
}

function openCreateContainer() {
  createForm.value = {
    image: '',
    name: '',
    restartPolicy: 'no',
    start: true,
  }
  createPortsText.value = ''
  createEnvText.value = ''
  createVolumesText.value = ''
  createCmdText.value = ''
  createEntrypointText.value = ''
  createVisible.value = true
}

async function submitCreateContainer() {
  if (!createForm.value.image?.trim()) {
    getUiApi().message.error('镜像名称不能为空。')
    return
  }

  creatingContainer.value = true
  try {
    const sessionId = requireSession()
    const payload: DockerCreateContainerPayload = {
      image: createForm.value.image.trim(),
      name: createForm.value.name?.trim() || undefined,
      ports: toLineList(createPortsText.value),
      env: toLineList(createEnvText.value),
      volumes: toLineList(createVolumesText.value),
      restartPolicy: createForm.value.restartPolicy || 'no',
      cmd: toLineList(createCmdText.value),
      entrypoint: toLineList(createEntrypointText.value),
      start: createForm.value.start === true,
    }

    const result = await dockerApi.createContainer(sessionId, payload)
    createVisible.value = false
    getUiApi().message.success(`容器创建成功：${result.containerId.slice(0, 12)}`)
    await loadDockerState()
  } catch (error) {
    console.error('Failed to create container', error)
    getUiApi().message.error(error instanceof Error ? error.message : '创建容器失败。')
  } finally {
    creatingContainer.value = false
  }
}

async function batchStartSelected() {
  if (selectedStoppedIds.value.length === 0) {
    getUiApi().message.warning('请选择未运行容器。')
    return
  }

  batchProcessing.value = true
  try {
    const sessionId = requireSession()
    const result = await dockerApi.batchStartContainers(sessionId, selectedStoppedIds.value)
    getUiApi().message.success(`批量启动完成，共处理 ${result.processed} 个容器。`)
    await loadDockerState()
  } catch (error) {
    console.error('Failed to batch start containers', error)
    getUiApi().message.error(error instanceof Error ? error.message : '批量启动失败。')
  } finally {
    batchProcessing.value = false
  }
}

async function batchStopSelected() {
  if (selectedRunningIds.value.length === 0) {
    getUiApi().message.warning('请选择运行中容器。')
    return
  }

  batchProcessing.value = true
  try {
    const sessionId = requireSession()
    const result = await dockerApi.batchStopContainers(sessionId, selectedRunningIds.value)
    getUiApi().message.success(`批量停止完成，共处理 ${result.processed} 个容器。`)
    await loadDockerState()
  } catch (error) {
    console.error('Failed to batch stop containers', error)
    getUiApi().message.error(error instanceof Error ? error.message : '批量停止失败。')
  } finally {
    batchProcessing.value = false
  }
}

async function removeStoppedContainers() {
  try {
    const sessionId = requireSession()
    const result = await dockerApi.removeStoppedContainers(sessionId)
    getUiApi().message.success(`已删除 ${result.removedCount} 个已停止容器。`)
    await loadDockerState()
  } catch (error) {
    console.error('Failed to remove stopped containers', error)
    getUiApi().message.error(error instanceof Error ? error.message : '删除已停止容器失败。')
  }
}

async function pruneImages(includeUnused: boolean) {
  try {
    const sessionId = requireSession()
    await dockerApi.pruneImages(sessionId, includeUnused)
    getUiApi().message.success(includeUnused ? '无引用镜像清理完成。' : 'Dangling 镜像清理完成。')
    await loadDockerState()
  } catch (error) {
    console.error('Failed to prune images', error)
    getUiApi().message.error(error instanceof Error ? error.message : '镜像清理失败。')
  }
}

onMounted(() => {
  void loadDockerState()
})

watch([logsVisible, logsAutoRefresh], () => {
  syncLogsRefreshTimer()
})

watch(logsTail, async (value, previous) => {
  if (value !== previous && logsVisible.value) {
    await refreshLogs()
  }
})
</script>

<template>
  <div class="flex h-full flex-col gap-[16px] overflow-auto bg-[linear-gradient(180deg,rgba(15,23,42,0.16),rgba(15,23,42,0.06))] p-[18px]">
    <div class="flex flex-col gap-[16px]">
      <div class="flex flex-wrap items-start justify-between gap-[16px]">
        <div>
          <div class="mb-[6px] flex items-center gap-[8px]">
            <NIcon :size="20"><Cube /></NIcon>
            <h2 class="m-0 text-[20px]">Docker 管理</h2>
          </div>
          <p class="m-0 text-[rgba(226,232,240,0.72)]">查看容器与镜像状态，并执行常见运维操作。</p>
        </div>

        <NSpace>
          <NButton quaternary @click="openCreateContainer">
            <template #icon>
              <NIcon><Add /></NIcon>
            </template>
            新建容器
          </NButton>
          <NInput
            v-model:value="pullImageName"
            class="w-[min(320px,60vw)] lt-sm:w-full"
            placeholder="例如 nginx:latest"
            @keydown.enter.prevent="pullImage"
          >
            <template #prefix>
              <NIcon><Download /></NIcon>
            </template>
          </NInput>
          <NButton type="primary" :loading="pullingImage" @click="pullImage">
            <template #icon>
              <NIcon><Upload /></NIcon>
            </template>
            拉取镜像
          </NButton>
          <NButton quaternary :loading="loading" @click="refresh">刷新</NButton>
        </NSpace>
      </div>

      <div class="docker-summary grid grid-cols-[repeat(4,minmax(0,1fr))] gap-[12px]">
        <NCard size="small" :bordered="false" class="rounded-[18px] bg-[rgba(15,23,42,0.72)]">
          <div class="text-[12px] text-[rgba(226,232,240,0.68)]">运行中容器</div>
          <div class="mt-[6px] text-[28px] font-700">{{ runningContainers }}</div>
        </NCard>
        <NCard size="small" :bordered="false" class="rounded-[18px] bg-[rgba(15,23,42,0.72)]">
          <div class="text-[12px] text-[rgba(226,232,240,0.68)]">已停止容器</div>
          <div class="mt-[6px] text-[28px] font-700">{{ stoppedContainers }}</div>
        </NCard>
        <NCard size="small" :bordered="false" class="rounded-[18px] bg-[rgba(15,23,42,0.72)]">
          <div class="text-[12px] text-[rgba(226,232,240,0.68)]">镜像总数</div>
          <div class="mt-[6px] text-[28px] font-700">{{ images.length }}</div>
        </NCard>
        <NCard size="small" :bordered="false" class="rounded-[18px] bg-[rgba(15,23,42,0.72)]">
          <div class="text-[12px] text-[rgba(226,232,240,0.68)]">悬空镜像</div>
          <div class="mt-[6px] text-[28px] font-700">{{ danglingImages }}</div>
        </NCard>
      </div>
    </div>

    <NSpin :show="loading" class="docker-body">
      <NResult
        v-if="dockerAvailable === false"
        status="warning"
        title="当前环境不可用"
        description="该服务器未安装 Docker，或当前会话无法访问 Docker 服务。"
      />

      <NTabs v-else v-model:value="activeTab" type="segment" animated class="docker-tabs">
        <NTabPane name="containers" tab="容器">
          <div class="container-tab-content">
            <div class="mb-[12px] flex flex-wrap items-start justify-between gap-[12px]">
              <NSpace>
                <NSelect
                  v-model:value="containerStatusFilter"
                  class="w-[128px]"
                  :options="containerStatusOptions"
                  size="small"
                />
                <NButton quaternary :loading="batchProcessing" @click="batchStartSelected">批量启动</NButton>
                <NButton quaternary :loading="batchProcessing" @click="batchStopSelected">批量停止</NButton>
                <NButton quaternary @click="removeStoppedContainers">清理已停止</NButton>
                <NButton quaternary @click="pruneImages(false)">清理悬空镜像</NButton>
                <NButton quaternary @click="pruneImages(true)">清理无引用镜像</NButton>
                <NTag round size="small">已选 {{ selectedContainerIds.length }}</NTag>
                <NTag round size="small">显示 {{ filteredContainers.length }} / {{ containers.length }}</NTag>
              </NSpace>
            </div>

            <div class="docker-table-shell">
              <NDataTable
                v-model:checked-row-keys="selectedContainerIds"
                class="docker-table"
                :single-line="false"
                :columns="containerColumns"
                :data="filteredContainers"
                :pagination="containerPagination"
                :row-key="containerRowKey"
                size="small"
              />
            </div>
          </div>
        </NTabPane>

        <NTabPane name="images" tab="镜像">
          <div class="image-tab-content">
            <div class="mb-[12px] text-[13px] text-[rgba(226,232,240,0.68)]">支持镜像重新打标签、查看构建历史和引用容器。</div>
            <div class="docker-table-shell">
              <NDataTable
                class="docker-table"
                :single-line="false"
                :columns="imageColumns"
                :data="images"
                :pagination="imagePagination"
                size="small"
              />
            </div>
          </div>
        </NTabPane>
      </NTabs>
    </NSpin>

    <NModal v-model:show="logsVisible" preset="card" :title="logsTitle" class="logs-modal" style="width: min(960px, 92vw)">
      <div class="mb-[12px] flex flex-wrap items-center gap-[10px]">
        <NInputNumber v-model:value="logsTail" :min="20" :max="5000" :step="20" placeholder="Tail" />
        <NInput v-model:value="logsKeyword" placeholder="过滤日志关键字" clearable />
        <NSwitch v-model:value="logsAutoRefresh" />
        <span class="text-[12px] text-[rgba(226,232,240,0.68)]">自动刷新</span>
        <span class="text-[12px] text-[rgba(226,232,240,0.68)]">更新于 {{ formatDateTime(logsLastUpdatedAt) }}</span>
        <NSpace>
          <NButton quaternary :loading="logsRefreshing" @click="refreshLogs()">刷新日志</NButton>
          <NButton quaternary @click="copyLogs">
            <template #icon>
              <NIcon><Copy /></NIcon>
            </template>
            复制
          </NButton>
          <NButton quaternary @click="downloadLogs">
            <template #icon>
              <NIcon><Download /></NIcon>
            </template>
            下载
          </NButton>
        </NSpace>
      </div>
      <NSpin :show="logsLoading">
        <pre class="mono-ui m-0 max-h-[65vh] overflow-auto whitespace-pre-wrap break-words rounded-[14px] bg-[rgba(2,6,23,0.9)] p-[14px] text-[12px] leading-[1.6] text-[#dbeafe]">{{ displayedLogs }}</pre>
      </NSpin>
    </NModal>

    <NModal
      v-model:show="inspectVisible"
      preset="card"
      :title="inspectTitle"
      class="inspect-modal"
      style="width: min(960px, 92vw)"
    >
      <NSpin :show="inspectLoading">
        <pre class="mono-ui m-0 max-h-[65vh] overflow-auto whitespace-pre-wrap break-words rounded-[14px] bg-[rgba(2,6,23,0.9)] p-[14px] text-[12px] leading-[1.6] text-[#dbeafe]">{{ inspectContent ? JSON.stringify(inspectContent, null, 2) : '' }}</pre>
      </NSpin>
    </NModal>

    <NModal
      v-model:show="createVisible"
      preset="card"
      title="新建容器"
      style="width: min(760px, 94vw)"
    >
      <NForm label-placement="top">
        <NGrid :cols="2" :x-gap="12">
          <NFormItemGi label="镜像">
            <NInput v-model:value="createForm.image" placeholder="例如 nginx:latest" />
          </NFormItemGi>
          <NFormItemGi label="容器名称">
            <NInput v-model:value="createForm.name" placeholder="可选" />
          </NFormItemGi>
        </NGrid>

        <NGrid :cols="2" :x-gap="12">
          <NFormItemGi label="重启策略">
            <NSelect
              v-model:value="createForm.restartPolicy"
              :options="[
                { label: 'no', value: 'no' },
                { label: 'always', value: 'always' },
                { label: 'unless-stopped', value: 'unless-stopped' },
                { label: 'on-failure', value: 'on-failure' },
              ]"
            />
          </NFormItemGi>
          <NFormItemGi label="创建后立即启动">
            <NSwitch v-model:value="createForm.start" />
          </NFormItemGi>
        </NGrid>

        <NFormItem label="端口映射">
          <NInput v-model:value="createPortsText" type="textarea" :rows="3" placeholder="每行一条，例如 8080:80" />
        </NFormItem>

        <NFormItem label="环境变量">
          <NInput v-model:value="createEnvText" type="textarea" :rows="3" placeholder="每行一条，例如 NODE_ENV=production" />
        </NFormItem>

        <NFormItem label="卷挂载">
          <NInput v-model:value="createVolumesText" type="textarea" :rows="3" placeholder="每行一条，例如 /host/data:/data" />
        </NFormItem>

        <NFormItem label="启动命令 CMD">
          <NInput v-model:value="createCmdText" type="textarea" :rows="2" placeholder="每行一个参数" />
        </NFormItem>

        <NFormItem label="Entrypoint">
          <NInput v-model:value="createEntrypointText" type="textarea" :rows="2" placeholder="每行一个参数" />
        </NFormItem>
      </NForm>

      <template #footer>
        <NSpace justify="end">
          <NButton @click="createVisible = false">取消</NButton>
          <NButton type="primary" :loading="creatingContainer" @click="submitCreateContainer">创建</NButton>
        </NSpace>
      </template>
    </NModal>

    <NModal v-model:show="renameVisible" preset="card" title="重命名容器" style="width: min(520px, 92vw)">
      <NForm label-placement="top">
        <NFormItem label="新名称">
          <NInput v-model:value="renamingContainerName" placeholder="输入新的容器名称" />
        </NFormItem>
      </NForm>

      <template #footer>
        <NSpace justify="end">
          <NButton @click="renameVisible = false">取消</NButton>
          <NButton type="primary" :loading="renamingContainer" @click="submitRenameContainer">保存</NButton>
        </NSpace>
      </template>
    </NModal>

    <NModal v-model:show="imageTagVisible" preset="card" title="镜像重新打标签" style="width: min(560px, 92vw)">
      <NForm label-placement="top">
        <NFormItem label="源镜像">
          <NInput v-model:value="imageTagSource" readonly />
        </NFormItem>
        <NFormItem label="目标标签">
          <NInput v-model:value="imageTagTarget" placeholder="例如 my-nginx:stable" />
        </NFormItem>
      </NForm>

      <template #footer>
        <NSpace justify="end">
          <NButton @click="imageTagVisible = false">取消</NButton>
          <NButton type="primary" :loading="imageTagging" @click="submitTagImage">确认</NButton>
        </NSpace>
      </template>
    </NModal>

    <NModal v-model:show="imageHistoryVisible" preset="card" :title="imageHistoryTitle" style="width: min(960px, 92vw)">
      <NSpin :show="imageHistoryLoading">
        <NDataTable
          :single-line="false"
          :columns="[
            { title: 'ID', key: 'id' },
            { title: '时间', key: 'createdSince' },
            { title: '大小', key: 'size' },
            { title: '命令', key: 'createdBy' },
            { title: '备注', key: 'comment' },
          ]"
          :data="imageHistoryItems"
          size="small"
        />
      </NSpin>
    </NModal>

    <NModal v-model:show="imageRefsVisible" preset="card" :title="imageRefsTitle" style="width: min(960px, 92vw)">
      <NSpin :show="imageRefsLoading">
        <NDataTable
          :single-line="false"
          :columns="[
            { title: '容器名', key: 'name' },
            { title: '镜像', key: 'image' },
            { title: '状态', key: 'status' },
            { title: 'State', key: 'state' },
          ]"
          :data="imageRefsItems"
          size="small"
        />
      </NSpin>
    </NModal>
  </div>
</template>

<style scoped>
.docker-body {
  flex: none;
}

.docker-body :deep(.n-spin-container),
.docker-body :deep(.n-spin-content) {
  overflow: visible;
}

.docker-body :deep(.n-spin-content) {
  display: block;
}

.docker-tabs {
  display: block;
}

.docker-tabs :deep(.n-tabs-content) {
  display: block;
  overflow: visible;
}

.docker-tabs :deep(.n-tabs-pane-wrapper),
.docker-tabs :deep(.n-tab-pane) {
  overflow: visible;
}

.container-tab-content,
.image-tab-content {
  display: flex;
  flex-direction: column;
}

.docker-table-shell {
  flex: none;
  overflow: visible;
}

.docker-table {
  min-width: 100%;
}

.container-port-summary {
  display: inline-block;
  max-width: 130px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  vertical-align: middle;
}

.container-port-popover {
  display: flex;
  flex-direction: column;
  gap: 6px;
  max-width: 360px;
}

.container-port-item {
  font-family: Consolas, 'Cascadia Mono', 'Courier New', monospace;
  font-size: 12px;
  line-height: 1.5;
  word-break: break-all;
}

.container-action-popover {
  max-width: 260px;
}

@media (max-width: 960px) {
  .docker-summary {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

}

@media (max-width: 640px) {
  .docker-summary {
    grid-template-columns: 1fr;
  }

}
</style>

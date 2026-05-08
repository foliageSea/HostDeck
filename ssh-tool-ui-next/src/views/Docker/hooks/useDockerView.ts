import { computed, onBeforeUnmount, onMounted, ref, watch, type UnwrapNestedRefs } from 'vue'
import type { DataTableColumns } from 'naive-ui'
import {
  dockerApi,
  type DockerContainer,
  type DockerContainerDiagnostic,
  type DockerContainerStatusFilter,
  type DockerContainerSummary,
  type DockerContainerStats,
  type DockerComposeProject,
  type DockerComposeProjectPayload,
  type DockerComposeService,
  type DockerCreateNetworkPayload,
  type DockerCreateVolumePayload,
  type DockerImageContainerRef,
  type DockerImageHistoryItem,
  type DockerImageSummary,
  type DockerImage,
  type DockerNetwork,
  type DockerVolume,
} from '@/api/docker'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useSshStore } from '@/stores/ssh'

export interface DockerViewProps {
  windowId?: string
  connectionId?: string
  host?: string
  username?: string
}

interface DangerActionConfirmOptions {
  title: string
  content: string
  positiveText: string
  action: () => Promise<void> | void
}

export function useDockerView(props: DockerViewProps) {
  const desktopStore = useDesktopStore()
  const sshStore = useSshStore()

  const activeTab = ref<'overview' | 'containers' | 'images' | 'networks' | 'volumes' | 'compose'>('overview')
  const loading = ref(false)
  const dockerAvailable = ref<boolean | null>(null)
  const containers = ref<DockerContainer[]>([])
  const containerStatusFilter = ref<DockerContainerStatusFilter>('all')
  const containerPage = ref(1)
  const containerPageSize = ref(8)
  const containerTotal = ref(0)
  const containerSummary = ref<DockerContainerSummary>({ total: 0, running: 0, stopped: 0 })
  const images = ref<DockerImage[]>([])
  const imagePage = ref(1)
  const imagePageSize = ref(8)
  const imageTotal = ref(0)
  const imageSummary = ref<DockerImageSummary>({ total: 0, dangling: 0 })
  const networks = ref<DockerNetwork[]>([])
  const volumes = ref<DockerVolume[]>([])
  const composeAvailable = ref<boolean | null>(null)
  const composeProjects = ref<DockerComposeProject[]>([])
  const composeServicesMap = ref<Record<string, DockerComposeService[]>>({})
  const composeServiceLoadingMap = ref<Record<string, boolean>>({})
  const composeActionLoadingMap = ref<Record<string, boolean>>({})
  const selectedComposeProjectName = ref('')
  const statsMap = ref<Record<string, DockerContainerStats>>({})
  const diagnosticsMap = ref<Record<string, DockerContainerDiagnostic>>({})
  const containerResourceLoadingMap = ref<Record<string, boolean>>({})
  const containerResourceLoadedMap = ref<Record<string, boolean>>({})
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
  const logsContainerId = ref('')
  const logsContainerName = ref('')
  const logsComposeProject = ref<DockerComposeProject | null>(null)
  const inspectVisible = ref(false)
  const inspectLoading = ref(false)
  const inspectTitle = ref('')
  const inspectContent = ref<unknown | null>(null)
  const pullingImage = ref(false)
  const pullImageName = ref('')
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
  let requestQueue = Promise.resolve()
  let pendingDockerStateLoad: Promise<void> | null = null

  const dockerPageSizes = [8, 16, 32, 50]
  const activeConnectionId = computed(() => props.connectionId ?? sshStore.connectionId)
  const runningContainers = computed(() => containerSummary.value.running)
  const stoppedContainers = computed(() => containerSummary.value.stopped)
  const danglingImages = computed(() => imageSummary.value.dangling)
  const containerPagination = computed(() => ({
    page: containerPage.value,
    pageSize: containerPageSize.value,
    itemCount: containerTotal.value,
    pageSizes: dockerPageSizes,
    showSizePicker: true,
  }))
  const imagePagination = computed(() => ({
    page: imagePage.value,
    pageSize: imagePageSize.value,
    itemCount: imageTotal.value,
    pageSizes: dockerPageSizes,
    showSizePicker: true,
  }))
  const containerStatusOptions = [
    { label: '全部状态', value: 'all' },
    { label: '运行中', value: 'running' },
    { label: '已停止', value: 'stopped' },
    { label: '已暂停', value: 'paused' },
    { label: '重启中', value: 'restarting' },
    { label: '已退出', value: 'exited' },
  ]
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

  function requireConnectionId() {
    const connectionId = activeConnectionId.value
    if (!connectionId) {
      throw new Error('当前没有可用的 Docker 连接。')
    }

    return connectionId
  }

  function queueDockerRequest<T>(action: () => Promise<T>) {
    const nextTask = requestQueue.catch(() => undefined).then(action)
    requestQueue = nextTask.then(
      () => undefined,
      () => undefined,
    )
    return nextTask
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

  function formatDateTime(value: Date | null) {
    if (!value) {
      return '-'
    }

    return value.toLocaleString('zh-CN')
  }

  function setActiveTab(value: 'overview' | 'containers' | 'images' | 'networks' | 'volumes' | 'compose') {
    activeTab.value = value
  }

  function setContainerStatusFilter(value: DockerContainerStatusFilter) {
    containerStatusFilter.value = value
  }

  function updateSelectedContainerIds(keys: Array<string | number>) {
    selectedContainerIds.value = keys.map((key) => String(key))
  }

  function getComposeConfigFiles(project: DockerComposeProject) {
    return project.configFiles
      .split(',')
      .map((file) => file.trim())
      .filter(Boolean)
  }

  function getComposeProjectPayload(project: DockerComposeProject): DockerComposeProjectPayload | null {
    const configFiles = getComposeConfigFiles(project)
    if (!project.name || configFiles.length === 0) {
      return null
    }

    return {
      configFiles,
      projectName: project.name,
      workingDir: project.workingDir || undefined,
    }
  }

  function getComposeStatusType(project: DockerComposeProject) {
    const status = project.status.toLowerCase()
    if (status.includes('running')) {
      return 'success'
    }
    if (status.includes('exited') || status.includes('stopped')) {
      return 'warning'
    }
    return 'default'
  }

  function getComposeServiceStatusType(service: DockerComposeService) {
    const state = `${service.state} ${service.status}`.toLowerCase()
    if (state.includes('running')) {
      return 'success'
    }
    if (state.includes('exit') || state.includes('stop')) {
      return 'warning'
    }
    return 'default'
  }

  function parseContainerHostPort(portText: string) {
    const hostSide = portText.split('->')[0]?.trim() ?? ''
    if (!hostSide || hostSide.includes('/')) {
      return null
    }

    const hostPort = hostSide.includes(':') ? hostSide.slice(hostSide.lastIndexOf(':') + 1) : hostSide
    const portNumber = Number(hostPort)
    if (!Number.isInteger(portNumber) || portNumber < 1 || portNumber > 65535) {
      return null
    }

    return hostPort
  }

  function getContainerPortLink(container: DockerContainer, portText: string) {
    const host = (props.host ?? sshStore.host).trim()
    const port = parseContainerHostPort(portText)
    const url = getContainerPortUrl(portText)

    if (!host || !port || !url) {
      return null
    }

    return {
      host,
      id: `${host}:${port}`,
      label: `${container.name}:${port}`,
      port,
      portText,
      url,
    }
  }

  function getContainerPortUrl(portText: string) {
    const host = (props.host ?? sshStore.host).trim()
    const hostPort = parseContainerHostPort(portText)

    if (!host || !hostPort) {
      return null
    }

    return `http://${host}:${hostPort}`
  }

  function openContainerPort(portText: string) {
    const url = getContainerPortUrl(portText)
    if (!url) {
      getUiApi().message.warning('该端口未映射宿主机端口，无法直接打开。')
      return
    }

    window.open(url, '_blank', 'noopener')
  }

  function isContainerPortPinned(portText: string) {
    const url = getContainerPortUrl(portText)
    return Boolean(url && desktopStore.isPortLinkPinned(url))
  }

  function toggleContainerPortDesktopPin(container: DockerContainer, portText: string) {
    const link = getContainerPortLink(container, portText)
    if (!link) {
      getUiApi().message.warning('该端口未映射宿主机端口，无法添加到桌面。')
      return
    }

    const pinned = desktopStore.togglePortLinkPin(link)
    getUiApi().message.success(pinned ? '已将端口链接添加到桌面。' : '已从桌面移除端口链接。')
  }

  const imageHistoryColumns: DataTableColumns<DockerImageHistoryItem> = [
    { title: 'ID', key: 'id', width: 180 },
    { title: '时间', key: 'createdSince', width: 140 },
    { title: '大小', key: 'size', width: 120 },
    { title: '命令', key: 'createdBy', width: 560 },
    { title: '备注', key: 'comment', width: 260 },
  ]

  const imageRefsColumns: DataTableColumns<DockerImageContainerRef> = [
    { title: '容器名', key: 'name' },
    { title: '镜像', key: 'image' },
    { title: '状态', key: 'status' },
    { title: 'State', key: 'state' },
  ]

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
    if (!logsContainerId.value && !logsComposeProject.value) {
      return
    }

    try {
      if (silent) {
        logsRefreshing.value = true
      } else {
        logsLoading.value = true
      }

      const connectionId = requireConnectionId()
      const composePayload = logsComposeProject.value ? getComposeProjectPayload(logsComposeProject.value) : null
      const result = composePayload
        ? await queueDockerRequest(() => dockerApi.getComposeLogs(connectionId, composePayload, logsTail.value))
        : await queueDockerRequest(() =>
            dockerApi.getContainerLogsAdvanced(connectionId, logsContainerId.value, {
              tail: logsTail.value,
              timestamps: true,
            }),
          )
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

  function resetDockerLists() {
    containers.value = []
    images.value = []
    networks.value = []
    volumes.value = []
    containerTotal.value = 0
    imageTotal.value = 0
    containerSummary.value = { total: 0, running: 0, stopped: 0 }
    imageSummary.value = { total: 0, dangling: 0 }
    selectedContainerIds.value = []
    statsMap.value = {}
    diagnosticsMap.value = {}
    containerResourceLoadingMap.value = {}
    containerResourceLoadedMap.value = {}
    composeProjects.value = []
    composeServicesMap.value = {}
    composeServiceLoadingMap.value = {}
    composeActionLoadingMap.value = {}
    selectedComposeProjectName.value = ''
  }

  async function loadContainersPage(page = containerPage.value, pageSize = containerPageSize.value) {
    const connectionId = requireConnectionId()
    const result = await queueDockerRequest(() =>
      dockerApi.listContainers(connectionId, {
        page,
        pageSize,
        status: containerStatusFilter.value,
      }),
    )

    containers.value = result.items
    containerPage.value = result.page
    containerPageSize.value = result.pageSize
    containerTotal.value = result.total
    containerSummary.value = result.summary ?? {
      total: result.total,
      running: 0,
      stopped: 0,
    }
    selectedContainerIds.value = selectedContainerIds.value.filter((id) => result.items.some((container) => container.id === id))
    statsMap.value = {}
    diagnosticsMap.value = {}
    containerResourceLoadingMap.value = {}
    containerResourceLoadedMap.value = {}
  }

  async function loadImagesPage(page = imagePage.value, pageSize = imagePageSize.value) {
    const connectionId = requireConnectionId()
    const result = await queueDockerRequest(() => dockerApi.listImages(connectionId, { page, pageSize }))

    images.value = result.items
    imagePage.value = result.page
    imagePageSize.value = result.pageSize
    imageTotal.value = result.total
    imageSummary.value = result.summary ?? {
      total: result.total,
      dangling: result.items.filter((image) => image.dangling).length,
    }
  }

  async function loadNetworks() {
    const connectionId = requireConnectionId()
    networks.value = await queueDockerRequest(() => dockerApi.listNetworks(connectionId))
  }

  async function loadVolumes() {
    const connectionId = requireConnectionId()
    volumes.value = await queueDockerRequest(() => dockerApi.listVolumes(connectionId))
  }

  async function loadDockerSection(action: () => Promise<void>, fallbackMessage: string) {
    loading.value = true
    try {
      await action()
    } catch (error) {
      console.error(fallbackMessage, error)
      getUiApi().message.error(error instanceof Error ? error.message : fallbackMessage)
    } finally {
      loading.value = false
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

  async function refreshContainerResource(containerId: string) {
    containerResourceLoadingMap.value = {
      ...containerResourceLoadingMap.value,
      [containerId]: true,
    }

    try {
      const connectionId = requireConnectionId()
      const [stats, diagnostics] = await Promise.all([
        queueDockerRequest(() => dockerApi.getContainerStats(connectionId, containerId)).catch(() => null),
        queueDockerRequest(() => dockerApi.getContainerDiagnostics(connectionId, [containerId])).catch(() => []),
      ])

      if (stats) {
        statsMap.value = {
          ...statsMap.value,
          [containerId]: stats,
        }
      }

      const diagnostic = diagnostics[0]
      if (diagnostic) {
        diagnosticsMap.value = {
          ...diagnosticsMap.value,
          [containerId]: diagnostic,
        }
      }

      containerResourceLoadedMap.value = {
        ...containerResourceLoadedMap.value,
        [containerId]: true,
      }
    } catch (error) {
      console.error('Failed to refresh container resource', error)
      getUiApi().message.error(error instanceof Error ? error.message : '加载容器资源失败。')
    } finally {
      containerResourceLoadingMap.value = {
        ...containerResourceLoadingMap.value,
        [containerId]: false,
      }
    }
  }

  async function loadDockerState() {
    if (pendingDockerStateLoad) {
      return pendingDockerStateLoad
    }

    const task = (async () => {
      loading.value = true

      try {
        const connectionId = requireConnectionId()
        const result = await queueDockerRequest(() => dockerApi.checkDocker(connectionId))
        dockerAvailable.value = result.available

        if (!result.available) {
          resetDockerLists()
          return
        }

        await loadContainersPage()
        await loadImagesPage()
        await loadNetworks()
        await loadVolumes()
        await loadComposeProjects()
      } catch (error) {
        console.error('Failed to load Docker state', error)
        dockerAvailable.value = false
        resetDockerLists()
        getUiApi().message.error(error instanceof Error ? error.message : '加载 Docker 数据失败。')
      } finally {
        loading.value = false
      }
    })()

    pendingDockerStateLoad = task.finally(() => {
      pendingDockerStateLoad = null
    })

    return pendingDockerStateLoad
  }

  async function refresh() {
    await loadDockerState()
  }

  async function refreshCompose() {
    await loadDockerSection(loadComposeProjects, '加载 Docker 编排失败。')
  }

  async function refreshNetworks() {
    await loadDockerSection(loadNetworks, '加载 Docker 网络失败。')
  }

  async function refreshVolumes() {
    await loadDockerSection(loadVolumes, '加载 Docker 存储卷失败。')
  }

  async function handleContainerPageChange(page: number) {
    await loadDockerSection(() => loadContainersPage(page, containerPageSize.value), '加载容器列表失败。')
  }

  async function handleContainerPageSizeChange(pageSize: number) {
    await loadDockerSection(() => loadContainersPage(1, pageSize), '加载容器列表失败。')
  }

  async function handleImagePageChange(page: number) {
    await loadDockerSection(() => loadImagesPage(page, imagePageSize.value), '加载镜像列表失败。')
  }

  async function handleImagePageSizeChange(pageSize: number) {
    await loadDockerSection(() => loadImagesPage(1, pageSize), '加载镜像列表失败。')
  }

  async function handleContainerAction(
    container: DockerContainer,
    action: 'start' | 'stop' | 'restart' | 'remove',
  ) {
    try {
      const connectionId = requireConnectionId()

      if (action === 'start') {
        await queueDockerRequest(() => dockerApi.startContainer(connectionId, container.id))
        getUiApi().message.success(`已启动容器 ${container.name}。`)
      }

      if (action === 'stop') {
        await queueDockerRequest(() => dockerApi.stopContainer(connectionId, container.id))
        getUiApi().message.success(`已停止容器 ${container.name}。`)
      }

      if (action === 'restart') {
        await queueDockerRequest(() => dockerApi.restartContainer(connectionId, container.id))
        getUiApi().message.success(`已重启容器 ${container.name}。`)
      }

      if (action === 'remove') {
        await queueDockerRequest(() => dockerApi.removeContainer(connectionId, container.id, true))
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
      const connectionId = requireConnectionId()

      if (action === 'pause') {
        await queueDockerRequest(() => dockerApi.pauseContainer(connectionId, container.id))
        getUiApi().message.success(`已暂停容器 ${container.name}。`)
      }

      if (action === 'unpause') {
        await queueDockerRequest(() => dockerApi.unpauseContainer(connectionId, container.id))
        getUiApi().message.success(`已恢复容器 ${container.name}。`)
      }

      await loadDockerState()
    } catch (error) {
      console.error(`Failed to ${action} container`, error)
      getUiApi().message.error(error instanceof Error ? error.message : '容器高级操作失败。')
    }
  }

  function confirmDangerAction(options: DangerActionConfirmOptions) {
    const dialog = getUiApi().dialog.warning({
      title: options.title,
      content: options.content,
      positiveText: options.positiveText,
      negativeText: '取消',
      onPositiveClick: async () => {
        dialog.loading = true
        try {
          await options.action()
        } finally {
          dialog.loading = false
        }
      },
    })
  }

  function confirmContainerAction(container: DockerContainer, action: 'start' | 'stop' | 'restart' | 'remove') {
    const actionTextMap = {
      remove: '删除',
      restart: '重启',
      start: '启动',
      stop: '停止',
    } as const

    confirmDangerAction({
      title: `${actionTextMap[action]}容器`,
      content: `确认${actionTextMap[action]}容器 ${container.name}？`,
      positiveText: actionTextMap[action],
      action: () => handleContainerAction(container, action),
    })
  }

  async function viewLogs(container: DockerContainer) {
    logsVisible.value = true
    logsTitle.value = `容器日志 · ${container.name}`
    logsContainerId.value = container.id
    logsContainerName.value = container.name
    logsComposeProject.value = null
    logsKeyword.value = ''
    logsLastUpdatedAt.value = null
    await refreshLogs()
  }

  async function viewComposeLogs(project: DockerComposeProject) {
    const payload = getComposeProjectPayload(project)
    if (!payload) {
      getUiApi().message.warning('该编排项目缺少 compose 配置文件路径，无法查看日志。')
      return
    }

    logsVisible.value = true
    logsTitle.value = `编排日志 · ${project.name}`
    logsContainerId.value = ''
    logsContainerName.value = project.name
    logsComposeProject.value = project
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
      const connectionId = requireConnectionId()
      inspectContent.value = await queueDockerRequest(() => dockerApi.inspectContainer(connectionId, container.id))
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
      const connectionId = requireConnectionId()

      desktopStore.openWindow('terminal', {
        connectionId,
        host: props.host ?? sshStore.host,
        startupCommand: `docker exec -it ${container.id} bash || docker exec -it ${container.id} sh`,
        title: `Shell · ${container.name}`,
        username: props.username ?? sshStore.username,
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
      const connectionId = requireConnectionId()
      await queueDockerRequest(() =>
        dockerApi.renameContainer(connectionId, renamingContainerId.value, renamingContainerName.value.trim()),
      )
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
      const connectionId = requireConnectionId()
      const result = await queueDockerRequest(() => dockerApi.recreateContainer(connectionId, container.id))
      getUiApi().message.success(`容器 ${result.name} 重建完成。`)
      await loadDockerState()
    } catch (error) {
      console.error('Failed to recreate container', error)
      getUiApi().message.error(error instanceof Error ? error.message : '容器重建失败。')
    }
  }

  async function removeImage(image: DockerImage) {
    try {
      const connectionId = requireConnectionId()
      await queueDockerRequest(() => dockerApi.removeImage(connectionId, image.id, true))
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
      const connectionId = requireConnectionId()
      await queueDockerRequest(() => dockerApi.tagImage(connectionId, imageTagSource.value.trim(), imageTagTarget.value.trim()))
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
      const connectionId = requireConnectionId()
      imageHistoryItems.value = await queueDockerRequest(() => dockerApi.getImageHistory(connectionId, image.id))
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
      const connectionId = requireConnectionId()
      imageRefsItems.value = await queueDockerRequest(() => dockerApi.getImageContainers(connectionId, image.id))
    } catch (error) {
      console.error('Failed to load image refs', error)
      getUiApi().message.error(error instanceof Error ? error.message : '获取镜像引用容器失败。')
    } finally {
      imageRefsLoading.value = false
    }
  }

  function confirmRemoveImage(image: DockerImage) {
    confirmDangerAction({
      title: '删除镜像',
      content: `确认删除镜像 ${image.repository}:${image.tag}？`,
      positiveText: '删除',
      action: () => removeImage(image),
    })
  }

  function confirmRemoveStoppedContainers() {
    confirmDangerAction({
      title: '清理已停止容器',
      content: '确认删除当前连接中所有已停止的容器？该操作不可撤销。',
      positiveText: '清理',
      action: () => removeStoppedContainers(),
    })
  }

  function confirmPruneImages(includeUnused: boolean) {
    confirmDangerAction({
      title: includeUnused ? '清理无引用镜像' : '清理悬空镜像',
      content: includeUnused
        ? '确认清理当前连接中所有未被容器引用的镜像？该操作可能影响后续快速启动。'
        : '确认清理当前连接中的所有 dangling 镜像？该操作不可撤销。',
      positiveText: '清理',
      action: () => pruneImages(includeUnused),
    })
  }

  async function pullImage() {
    if (!pullImageName.value.trim()) {
      return
    }

    pullingImage.value = true
    try {
      const connectionId = requireConnectionId()
      await queueDockerRequest(() => dockerApi.pullImage(connectionId, pullImageName.value.trim()))
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

  async function handleComposeProjectAction(project: DockerComposeProject, action: 'up' | 'stop' | 'restart' | 'down') {
    const payload = getComposeProjectPayload(project)
    if (!payload) {
      getUiApi().message.warning('该编排项目缺少 compose 配置文件路径，无法执行操作。')
      return
    }

    composeActionLoadingMap.value = {
      ...composeActionLoadingMap.value,
      [project.name]: true,
    }

    try {
      const connectionId = requireConnectionId()
      if (action === 'up') {
        await queueDockerRequest(() => dockerApi.upComposeProject(connectionId, payload))
        getUiApi().message.success(`已启动编排项目 ${project.name}。`)
      }
      if (action === 'stop') {
        await queueDockerRequest(() => dockerApi.stopComposeProject(connectionId, payload))
        getUiApi().message.success(`已停止编排项目 ${project.name}。`)
      }
      if (action === 'restart') {
        await queueDockerRequest(() => dockerApi.restartComposeProject(connectionId, payload))
        getUiApi().message.success(`已重启编排项目 ${project.name}。`)
      }
      if (action === 'down') {
        await queueDockerRequest(() => dockerApi.downComposeProject(connectionId, payload))
        getUiApi().message.success(`已下线编排项目 ${project.name}。`)
      }

      await loadDockerState()
    } catch (error) {
      console.error(`Failed to ${action} compose project`, error)
      getUiApi().message.error(error instanceof Error ? error.message : '编排操作失败。')
    } finally {
      composeActionLoadingMap.value = {
        ...composeActionLoadingMap.value,
        [project.name]: false,
      }
    }
  }

  function confirmComposeProjectAction(project: DockerComposeProject, action: 'up' | 'stop' | 'restart' | 'down') {
    const actionTextMap = {
      down: '下线',
      restart: '重启',
      stop: '停止',
      up: '启动',
    } as const

    confirmDangerAction({
      title: `${actionTextMap[action]}编排项目`,
      content: `确认${actionTextMap[action]}编排项目 ${project.name}？`,
      positiveText: actionTextMap[action],
      action: () => handleComposeProjectAction(project, action),
    })
  }

  function openCreateContainer() {
    try {
      const connectionId = requireConnectionId()
      desktopStore.openWindow('docker-create-container', {
        connectionId,
        host: props.host ?? sshStore.host,
        title: '新建容器',
        username: props.username ?? sshStore.username,
      })
    } catch (error) {
      console.error('Failed to open create container window', error)
      getUiApi().message.error(error instanceof Error ? error.message : '打开新建容器窗口失败。')
    }
  }

  function openCreateComposeProject() {
    try {
      const connectionId = requireConnectionId()
      desktopStore.openWindow('docker-create-compose', {
        connectionId,
        host: props.host ?? sshStore.host,
        title: '新建编排',
        username: props.username ?? sshStore.username,
      })
    } catch (error) {
      console.error('Failed to open create compose window', error)
      getUiApi().message.error(error instanceof Error ? error.message : '打开新建编排窗口失败。')
    }
  }

  async function loadComposeProjects() {
    const connectionId = requireConnectionId()
    const result = await queueDockerRequest(() => dockerApi.checkCompose(connectionId))
    composeAvailable.value = result.available

    if (!result.available) {
      composeProjects.value = []
      composeServicesMap.value = {}
      return
    }

    composeProjects.value = await queueDockerRequest(() => dockerApi.listComposeProjects(connectionId))
    if (composeProjects.value.length > 0 && !selectedComposeProjectName.value) {
      selectedComposeProjectName.value = composeProjects.value[0].name
    }
  }

  async function refreshComposeServices(project: DockerComposeProject) {
    const payload = getComposeProjectPayload(project)
    if (!payload) {
      getUiApi().message.warning('该编排项目缺少 compose 配置文件路径，无法加载服务。')
      return
    }

    composeServiceLoadingMap.value = {
      ...composeServiceLoadingMap.value,
      [project.name]: true,
    }

    try {
      const connectionId = requireConnectionId()
      const services = await queueDockerRequest(() => dockerApi.listComposeServices(connectionId, payload))
      composeServicesMap.value = {
        ...composeServicesMap.value,
        [project.name]: services,
      }
    } catch (error) {
      console.error('Failed to load compose services', error)
      getUiApi().message.error(error instanceof Error ? error.message : '加载编排服务失败。')
    } finally {
      composeServiceLoadingMap.value = {
        ...composeServiceLoadingMap.value,
        [project.name]: false,
      }
    }
  }

  async function batchStartSelected() {
    if (selectedStoppedIds.value.length === 0) {
      getUiApi().message.warning('请选择未运行容器。')
      return
    }

    batchProcessing.value = true
    try {
      const connectionId = requireConnectionId()
      const result = await queueDockerRequest(() => dockerApi.batchStartContainers(connectionId, selectedStoppedIds.value))
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
      const connectionId = requireConnectionId()
      const result = await queueDockerRequest(() => dockerApi.batchStopContainers(connectionId, selectedRunningIds.value))
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
      const connectionId = requireConnectionId()
      const result = await queueDockerRequest(() => dockerApi.removeStoppedContainers(connectionId))
      getUiApi().message.success(`已删除 ${result.removedCount} 个已停止容器。`)
      await loadDockerState()
    } catch (error) {
      console.error('Failed to remove stopped containers', error)
      getUiApi().message.error(error instanceof Error ? error.message : '删除已停止容器失败。')
    }
  }

  async function pruneImages(includeUnused: boolean) {
    try {
      const connectionId = requireConnectionId()
      await queueDockerRequest(() => dockerApi.pruneImages(connectionId, includeUnused))
      getUiApi().message.success(includeUnused ? '无引用镜像清理完成。' : 'Dangling 镜像清理完成。')
      await loadDockerState()
    } catch (error) {
      console.error('Failed to prune images', error)
      getUiApi().message.error(error instanceof Error ? error.message : '镜像清理失败。')
    }
  }

  async function createNetwork(payload: DockerCreateNetworkPayload) {
    try {
      const connectionId = requireConnectionId()
      const result = await queueDockerRequest(() => dockerApi.createNetwork(connectionId, payload))
      getUiApi().message.success(result.warning ? `网络已创建，返回警告：${result.warning}` : 'Docker 网络创建成功。')
      await loadNetworks()
      return true
    } catch (error) {
      console.error('Failed to create network', error)
      getUiApi().message.error(error instanceof Error ? error.message : '创建 Docker 网络失败。')
      return false
    }
  }

  async function createVolume(payload: DockerCreateVolumePayload) {
    try {
      const connectionId = requireConnectionId()
      const result = await queueDockerRequest(() => dockerApi.createVolume(connectionId, payload))
      getUiApi().message.success(result.warning ? `存储卷已创建，返回警告：${result.warning}` : 'Docker 存储卷创建成功。')
      await loadVolumes()
      return true
    } catch (error) {
      console.error('Failed to create volume', error)
      getUiApi().message.error(error instanceof Error ? error.message : '创建 Docker 存储卷失败。')
      return false
    }
  }

  async function viewNetworkInspect(network: DockerNetwork) {
    inspectVisible.value = true
    inspectLoading.value = true
    inspectTitle.value = `Network Inspect · ${network.name}`
    inspectContent.value = null

    try {
      const connectionId = requireConnectionId()
      inspectContent.value = await queueDockerRequest(() => dockerApi.inspectNetwork(connectionId, network.id))
    } catch (error) {
      console.error('Failed to inspect network', error)
      getUiApi().message.error(error instanceof Error ? error.message : '网络 Inspect 加载失败。')
    } finally {
      inspectLoading.value = false
    }
  }

  async function viewVolumeInspect(volume: DockerVolume) {
    inspectVisible.value = true
    inspectLoading.value = true
    inspectTitle.value = `Volume Inspect · ${volume.name}`
    inspectContent.value = null

    try {
      const connectionId = requireConnectionId()
      inspectContent.value = await queueDockerRequest(() => dockerApi.inspectVolume(connectionId, volume.name))
    } catch (error) {
      console.error('Failed to inspect volume', error)
      getUiApi().message.error(error instanceof Error ? error.message : '存储卷 Inspect 加载失败。')
    } finally {
      inspectLoading.value = false
    }
  }

  async function removeNetwork(network: DockerNetwork) {
    try {
      const connectionId = requireConnectionId()
      await queueDockerRequest(() => dockerApi.removeNetwork(connectionId, network.id))
      getUiApi().message.success(`已删除网络 ${network.name}。`)
      await loadNetworks()
    } catch (error) {
      console.error('Failed to remove network', error)
      getUiApi().message.error(error instanceof Error ? error.message : '删除 Docker 网络失败。')
    }
  }

  async function removeVolume(volume: DockerVolume) {
    try {
      const connectionId = requireConnectionId()
      await queueDockerRequest(() => dockerApi.removeVolume(connectionId, volume.name))
      getUiApi().message.success(`已删除存储卷 ${volume.name}。`)
      await loadVolumes()
    } catch (error) {
      console.error('Failed to remove volume', error)
      getUiApi().message.error(error instanceof Error ? error.message : '删除 Docker 存储卷失败。')
    }
  }

  function confirmRemoveNetwork(network: DockerNetwork) {
    confirmDangerAction({
      title: '删除网络',
      content: `确认删除网络 ${network.name}？若仍有容器连接到该网络，操作将失败。`,
      positiveText: '删除',
      action: () => removeNetwork(network),
    })
  }

  function confirmRemoveVolume(volume: DockerVolume) {
    confirmDangerAction({
      title: '删除存储卷',
      content: `确认删除存储卷 ${volume.name}？若仍被容器使用，操作将失败。`,
      positiveText: '删除',
      action: () => removeVolume(volume),
    })
  }

  async function updateNetworkConnection(network: DockerNetwork, container: string, disconnect = false, force = false) {
    try {
      const connectionId = requireConnectionId()
      const trimmedContainer = container.trim()
      if (!trimmedContainer) {
        getUiApi().message.warning('请输入容器 ID 或容器名称。')
        return false
      }

      if (disconnect) {
        await queueDockerRequest(() => dockerApi.disconnectNetwork(connectionId, network.id, { container: trimmedContainer, force }))
        getUiApi().message.success(`已将容器 ${trimmedContainer} 从网络 ${network.name} 断开。`)
      } else {
        await queueDockerRequest(() => dockerApi.connectNetwork(connectionId, network.id, { container: trimmedContainer }))
        getUiApi().message.success(`已将容器 ${trimmedContainer} 连接到网络 ${network.name}。`)
      }

      await loadNetworks()
      return true
    } catch (error) {
      console.error('Failed to update network connection', error)
      getUiApi().message.error(error instanceof Error ? error.message : '更新 Docker 网络连接失败。')
      return false
    }
  }

  async function pruneNetworks() {
    try {
      const connectionId = requireConnectionId()
      const result = await queueDockerRequest(() => dockerApi.pruneNetworks(connectionId))
      getUiApi().message.success(`网络清理完成，共删除 ${result.deletedCount} 个未使用网络。`)
      await loadNetworks()
    } catch (error) {
      console.error('Failed to prune networks', error)
      getUiApi().message.error(error instanceof Error ? error.message : 'Docker 网络清理失败。')
    }
  }

  async function pruneVolumes() {
    try {
      const connectionId = requireConnectionId()
      const result = await queueDockerRequest(() => dockerApi.pruneVolumes(connectionId))
      getUiApi().message.success(`存储卷清理完成，共删除 ${result.deletedCount} 个未使用存储卷。`)
      await loadVolumes()
    } catch (error) {
      console.error('Failed to prune volumes', error)
      getUiApi().message.error(error instanceof Error ? error.message : 'Docker 存储卷清理失败。')
    }
  }

  function confirmPruneNetworks() {
    confirmDangerAction({
      title: '清理未使用网络',
      content: '确认清理当前连接中的所有未使用 Docker 网络？该操作不可撤销。',
      positiveText: '清理',
      action: () => pruneNetworks(),
    })
  }

  function confirmPruneVolumes() {
    confirmDangerAction({
      title: '清理未使用存储卷',
      content: '确认清理当前连接中的所有未使用 Docker 存储卷？该操作不可撤销。',
      positiveText: '清理',
      action: () => pruneVolumes(),
    })
  }

  function handleContainerCreated(event: Event) {
    const detail = (event as CustomEvent<{ connectionId?: string }>).detail
    if (detail?.connectionId && detail.connectionId !== activeConnectionId.value) {
      return
    }

    void loadDockerState()
  }

  function handleComposeCreated(event: Event) {
    const detail = (event as CustomEvent<{ connectionId?: string; project?: DockerComposeProject }>).detail
    if (detail?.connectionId && detail.connectionId !== activeConnectionId.value) {
      return
    }

    if (detail?.project) {
      const nextProjects = composeProjects.value.filter((project) => project.name !== detail.project?.name)
      composeProjects.value = [detail.project, ...nextProjects]
      selectedComposeProjectName.value = detail.project.name
      composeAvailable.value = true
    }

    void loadDockerState()
  }

  onMounted(() => {
    void loadDockerState()
    window.addEventListener('docker:container-created', handleContainerCreated)
    window.addEventListener('docker:compose-created', handleComposeCreated)
  })

  onBeforeUnmount(() => {
    if (logsRefreshTimer) {
      clearInterval(logsRefreshTimer)
      logsRefreshTimer = null
    }
    window.removeEventListener('docker:container-created', handleContainerCreated)
    window.removeEventListener('docker:compose-created', handleComposeCreated)
  })

  watch([logsVisible, logsAutoRefresh], () => {
    syncLogsRefreshTimer()
  })

  watch(containerStatusFilter, async () => {
    selectedContainerIds.value = []
    await loadDockerSection(() => loadContainersPage(1, containerPageSize.value), '加载容器列表失败。')
  })

  watch(logsTail, async (value, previous) => {
    if (value !== previous && logsVisible.value) {
      await refreshLogs()
    }
  })

  return {
    activeTab,
    batchProcessing,
    batchStartSelected,
    batchStopSelected,
    composeActionLoadingMap,
    composeAvailable,
    composeProjects,
    composeServiceLoadingMap,
    composeServicesMap,
    confirmComposeProjectAction,
    confirmPruneImages,
    confirmPruneNetworks,
    confirmPruneVolumes,
    confirmContainerAction,
    confirmRemoveImage,
    confirmRemoveNetwork,
    confirmRemoveStoppedContainers,
    confirmRemoveVolume,
    containerPage,
    containerPagination,
    containerResourceLoadedMap,
    containerResourceLoadingMap,
    containers,
    containerStatusFilter,
    containerStatusOptions,
    containerSummary,
    containerTotal,
    copyLogs,
    createNetwork,
    createVolume,
    danglingImages,
    displayedLogs,
    dockerAvailable,
    downloadLogs,
    diagnosticsMap,
    enterShell,
    formatDateTime,
    formatTime,
    getComposeConfigFiles,
    getComposeServiceStatusType,
    getComposeStatusType,
    getContainerPortUrl,
    handleContainerAdvancedAction,
    handleContainerPageChange,
    handleContainerPageSizeChange,
    handleImagePageChange,
    handleImagePageSizeChange,
    imageHistoryColumns,
    imageHistoryItems,
    imageHistoryLoading,
    imageHistoryTitle,
    imageHistoryVisible,
    imagePage,
    imagePagination,
    imageRefsColumns,
    imageRefsItems,
    imageRefsLoading,
    imageRefsTitle,
    imageRefsVisible,
    imageSummary,
    imageTagging,
    imageTagSource,
    imageTagTarget,
    imageTagVisible,
    imageTotal,
    images,
    inspectContent,
    inspectLoading,
    inspectTitle,
    inspectVisible,
    isContainerPortPinned,
    loading,
    logsAutoRefresh,
    logsContainerName,
    logsKeyword,
    logsLastUpdatedAt,
    logsLoading,
    logsRefreshing,
    logsTail,
    logsTitle,
    logsVisible,
    networks,
    openImageTagDialog,
    openContainerPort,
    openCreateComposeProject,
    openCreateContainer,
    openRenameDialog,
    pullImage,
    pullingImage,
    pullImageName,
    requireConnectionId,
    refresh,
    refreshCompose,
    refreshComposeServices,
    refreshContainerResource,
    refreshLogs,
    refreshNetworks,
    refreshVolumes,
    recreateContainer,
    renameVisible,
    renamingContainer,
    renamingContainerName,
    runningContainers,
    selectedComposeProjectName,
    selectedContainerIds,
    setActiveTab,
    setContainerStatusFilter,
    statsMap,
    stoppedContainers,
    submitRenameContainer,
    submitTagImage,
    toggleContainerPortDesktopPin,
    updateNetworkConnection,
    updateSelectedContainerIds,
    viewImageHistory,
    viewImageRefs,
    viewComposeLogs,
    viewInspect,
    viewLogs,
    viewNetworkInspect,
    viewVolumeInspect,
    volumes,
  }
}

export type DockerViewController = UnwrapNestedRefs<ReturnType<typeof useDockerView>>

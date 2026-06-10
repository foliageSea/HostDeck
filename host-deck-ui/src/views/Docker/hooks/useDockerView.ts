import { computed, onBeforeUnmount, onMounted, ref, watch, type UnwrapNestedRefs } from 'vue'
import {
  dockerApi,
  type DockerContainer,
  type DockerContainerDiagnostic,
  type DockerContainerStatusFilter,
  type DockerContainerSummary,
  type DockerContainerStats,
  type DockerComposeProject,
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
import { useUploadCenterStore } from '@/stores/upload-center'

import { imageHistoryColumns, imageRefsColumns } from './dockerViewColumns'
import {
  createLoadedTabs,
  formatDateTime,
  formatTime,
  getComposeConfigFiles,
  getComposeProjectPayload,
  getComposeServiceStatusType,
  getComposeStatusType,
  parseContainerHostPort,
} from './dockerViewHelpers'
import type { DangerActionConfirmOptions, DockerTabName, DockerViewProps } from './dockerViewTypes'

export type { DockerViewProps } from './dockerViewTypes'

export function useDockerView(props: DockerViewProps) {
  const desktopStore = useDesktopStore()
  const sshStore = useSshStore()
  const uploadCenterStore = useUploadCenterStore()

  const activeTab = ref<DockerTabName>('overview')
  const loading = ref(false)
  const dockerAvailable = ref<boolean | null>(null)
  const loadedTabs = ref<Record<DockerTabName, boolean>>(createLoadedTabs())
  const containers = ref<DockerContainer[]>([])
  const containerSearchKeyword = ref('')
  const containerStatusFilter = ref<DockerContainerStatusFilter>('all')
  const containerPage = ref(1)
  const containerPageSize = ref(8)
  const containerTotal = ref(0)
  const containerSummary = ref<DockerContainerSummary>({ total: 0, running: 0, stopped: 0 })
  const images = ref<DockerImage[]>([])
  const imageSearchKeyword = ref('')
  const imagePage = ref(1)
  const imagePageSize = ref(8)
  const imageTotal = ref(0)
  const imageSummary = ref<DockerImageSummary>({ total: 0, dangling: 0 })
  const networks = ref<DockerNetwork[]>([])
  const networkSearchKeyword = ref('')
  const volumes = ref<DockerVolume[]>([])
  const volumeSearchKeyword = ref('')
  const composeAvailable = ref<boolean | null>(null)
  const composeProjects = ref<DockerComposeProject[]>([])
  const composeSearchKeyword = ref('')
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
  const importingImage = ref(false)
  const pullingImage = ref(false)
  const pullImageName = ref('')
  const imageTagVisible = ref(false)
  const imageTagging = ref(false)
  const imageTagSource = ref('')
  const imageTagTarget = ref('')
  const imageExportingMap = ref<Record<string, boolean>>({})
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
  let pendingDockerCheck: Promise<boolean> | null = null
  const pendingTabLoads: Partial<Record<DockerTabName, Promise<void>>> = {}

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
    containers.value
      .filter((item) => selectedContainerIds.value.includes(item.id) && item.state !== 'running')
      .map((item) => item.id),
  )
  const selectedRunningIds = computed(() =>
    containers.value
      .filter((item) => selectedContainerIds.value.includes(item.id) && item.state === 'running')
      .map((item) => item.id),
  )
  const filteredNetworks = computed(() => {
    const keyword = networkSearchKeyword.value.trim().toLowerCase()
    if (!keyword) {
      return networks.value
    }

    return networks.value.filter((network) =>
      [
        network.id,
        network.name,
        network.driver,
        network.scope,
        ...network.connectedContainerNames,
      ].some((value) => value.toLowerCase().includes(keyword)),
    )
  })
  const filteredVolumes = computed(() => {
    const keyword = volumeSearchKeyword.value.trim().toLowerCase()
    if (!keyword) {
      return volumes.value
    }

    return volumes.value.filter((volume) =>
      [volume.name, volume.driver, volume.scope, volume.mountpoint, String(volume.refCount)].some(
        (value) => value.toLowerCase().includes(keyword),
      ),
    )
  })
  const filteredComposeProjects = computed(() => {
    const keyword = composeSearchKeyword.value.trim().toLowerCase()
    if (!keyword) {
      return composeProjects.value
    }

    return composeProjects.value.filter((project) =>
      [project.name, project.status, project.configFiles, project.workingDir].some((value) =>
        value.toLowerCase().includes(keyword),
      ),
    )
  })
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

  function setActiveTab(value: DockerTabName) {
    activeTab.value = value
    void loadTabData(value)
  }

  function setContainerStatusFilter(value: DockerContainerStatusFilter) {
    containerStatusFilter.value = value
  }

  function setContainerSearchKeyword(value: string) {
    containerSearchKeyword.value = value
  }

  function setImageSearchKeyword(value: string) {
    imageSearchKeyword.value = value
  }

  function updateSelectedContainerIds(keys: Array<string | number>) {
    selectedContainerIds.value = keys.map((key) => String(key))
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

  function getImageRef(image: DockerImage) {
    const repository = image.repository.trim()
    const tag = image.tag.trim()

    if (repository && tag && repository !== '<none>' && tag !== '<none>') {
      return `${repository}:${tag}`
    }

    return image.id
  }

  function getImageExportFilename(image: DockerImage) {
    const name = getImageRef(image)
      .replace(/[^A-Za-z0-9._-]+/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_+|_+$/g, '')

    return `${name || 'docker-image'}.tar`
  }

  function parseDockerSize(value: string) {
    const match = value.trim().match(/^(\d+(?:\.\d+)?)\s*([KMGTPE]?B)$/i)
    if (!match) {
      return 0
    }

    const amount = Number(match[1])
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB']
    const unitIndex = units.indexOf(match[2].toUpperCase())
    if (!Number.isFinite(amount) || unitIndex < 0) {
      return 0
    }

    return Math.round(amount * 1024 ** unitIndex)
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
      const composePayload = logsComposeProject.value
        ? getComposeProjectPayload(logsComposeProject.value)
        : null
      const result = composePayload
        ? await queueDockerRequest(() =>
            dockerApi.getComposeLogs(connectionId, composePayload, logsTail.value),
          )
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
    imageExportingMap.value = {}
    composeProjects.value = []
    composeServicesMap.value = {}
    composeServiceLoadingMap.value = {}
    composeActionLoadingMap.value = {}
    selectedComposeProjectName.value = ''
    loadedTabs.value = createLoadedTabs()
  }

  async function loadContainersPage(
    page = containerPage.value,
    pageSize = containerPageSize.value,
  ) {
    const connectionId = requireConnectionId()
    const result = await queueDockerRequest(() =>
      dockerApi.listContainers(connectionId, {
        page,
        pageSize,
        status: containerStatusFilter.value,
        keyword: containerSearchKeyword.value.trim() || undefined,
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
    selectedContainerIds.value = selectedContainerIds.value.filter((id) =>
      result.items.some((container) => container.id === id),
    )
    statsMap.value = {}
    diagnosticsMap.value = {}
    containerResourceLoadingMap.value = {}
    containerResourceLoadedMap.value = {}
  }

  async function loadImagesPage(page = imagePage.value, pageSize = imagePageSize.value) {
    const connectionId = requireConnectionId()
    const result = await queueDockerRequest(() =>
      dockerApi.listImages(connectionId, {
        page,
        pageSize,
        keyword: imageSearchKeyword.value.trim() || undefined,
      }),
    )

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

  function markTabsStale(...tabs: DockerTabName[]) {
    loadedTabs.value = tabs.reduce((result, tab) => ({ ...result, [tab]: false }), loadedTabs.value)
  }

  function getTabLoadMessage(tab: DockerTabName) {
    if (tab === 'containers') {
      return '加载容器列表失败。'
    }
    if (tab === 'images') {
      return '加载镜像列表失败。'
    }
    if (tab === 'networks') {
      return '加载 Docker 网络失败。'
    }
    if (tab === 'volumes') {
      return '加载 Docker 存储卷失败。'
    }
    if (tab === 'compose') {
      return '加载 Docker 编排失败。'
    }
    return '加载 Docker 数据失败。'
  }

  async function checkDockerAvailability() {
    if (pendingDockerCheck) {
      return pendingDockerCheck
    }

    const task = (async () => {
      try {
        const connectionId = requireConnectionId()
        const result = await queueDockerRequest(() => dockerApi.checkDocker(connectionId))
        dockerAvailable.value = result.available

        if (!result.available) {
          resetDockerLists()
        }

        return result.available
      } catch (error) {
        console.error('Failed to check Docker availability', error)
        dockerAvailable.value = false
        resetDockerLists()
        getUiApi().message.error(error instanceof Error ? error.message : '加载 Docker 数据失败。')
        return false
      }
    })()

    pendingDockerCheck = task.finally(() => {
      pendingDockerCheck = null
    })

    return pendingDockerCheck
  }

  async function loadTabData(tab: DockerTabName, force = false) {
    if (!force && loadedTabs.value[tab]) {
      return
    }

    if (pendingTabLoads[tab]) {
      return pendingTabLoads[tab]
    }

    const task = (async () => {
      loading.value = true

      try {
        const available = dockerAvailable.value === true ? true : await checkDockerAvailability()
        if (!available) {
          return
        }

        if (tab === 'containers') {
          await loadContainersPage(containerPage.value, containerPageSize.value)
        } else if (tab === 'images') {
          await loadImagesPage(imagePage.value, imagePageSize.value)
        } else if (tab === 'networks') {
          await loadNetworks()
        } else if (tab === 'volumes') {
          await loadVolumes()
        } else if (tab === 'compose') {
          await loadComposeProjects()
        } else {
          await loadContainersPage()
          await loadImagesPage()
          await loadNetworks()
          await loadVolumes()
          await loadComposeProjects()
        }

        loadedTabs.value = {
          ...loadedTabs.value,
          [tab]: true,
        }
      } catch (error) {
        console.error(getTabLoadMessage(tab), error)
        getUiApi().message.error(error instanceof Error ? error.message : getTabLoadMessage(tab))
      } finally {
        loading.value = false
      }
    })()

    pendingTabLoads[tab] = task.finally(() => {
      delete pendingTabLoads[tab]
    })

    return pendingTabLoads[tab]
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
        queueDockerRequest(() => dockerApi.getContainerStats(connectionId, containerId)).catch(
          () => null,
        ),
        queueDockerRequest(() =>
          dockerApi.getContainerDiagnostics(connectionId, [containerId]),
        ).catch(() => []),
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
    await loadTabData('overview', true)
  }

  async function refresh() {
    await loadDockerState()
  }

  async function refreshContainers() {
    await loadTabData('containers', true)
  }

  async function refreshImages() {
    await loadTabData('images', true)
  }

  async function refreshActiveTab() {
    await loadTabData(activeTab.value, true)
  }

  async function refreshTabsAfterChange(...tabs: DockerTabName[]) {
    markTabsStale('overview', ...tabs)

    if (activeTab.value === 'overview' || tabs.includes(activeTab.value)) {
      await loadTabData(activeTab.value, true)
    }
  }

  async function refreshCompose() {
    await loadTabData('compose', true)
  }

  async function refreshNetworks() {
    await loadTabData('networks', true)
  }

  async function refreshVolumes() {
    await loadTabData('volumes', true)
  }

  async function handleContainerPageChange(page: number) {
    await loadDockerSection(
      () => loadContainersPage(page, containerPageSize.value),
      '加载容器列表失败。',
    )
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

      await refreshTabsAfterChange('containers')
    } catch (error) {
      console.error(`Failed to ${action} container`, error)
      getUiApi().message.error(error instanceof Error ? error.message : '容器操作失败。')
    }
  }

  async function handleContainerAdvancedAction(
    container: DockerContainer,
    action: 'pause' | 'unpause',
  ) {
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

      await refreshTabsAfterChange('containers')
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

  function confirmContainerAction(
    container: DockerContainer,
    action: 'start' | 'stop' | 'restart' | 'remove',
  ) {
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
      inspectContent.value = await queueDockerRequest(() =>
        dockerApi.inspectContainer(connectionId, container.id),
      )
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
        dockerApi.renameContainer(
          connectionId,
          renamingContainerId.value,
          renamingContainerName.value.trim(),
        ),
      )
      renameVisible.value = false
      getUiApi().message.success('容器重命名成功。')
      await refreshTabsAfterChange('containers')
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
      const result = await queueDockerRequest(() =>
        dockerApi.recreateContainer(connectionId, container.id),
      )
      getUiApi().message.success(`容器 ${result.name} 重建完成。`)
      await refreshTabsAfterChange('containers')
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
      await refreshTabsAfterChange('images')
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

  async function exportImage(image: DockerImage) {
    const imageRef = getImageRef(image)
    const connectionId = requireConnectionId()
    const filename = getImageExportFilename(image)
    const estimatedTotal = parseDockerSize(image.size)
    const batchId = uploadCenterStore.createBatch(
      connectionId,
      'Docker 镜像导出',
      [{ name: filename, path: imageRef, size: estimatedTotal }],
      'docker-image-export',
    )
    const task = uploadCenterStore.batches.find((item) => item.id === batchId)?.tasks[0]
    const controller = new AbortController()

    imageExportingMap.value = {
      ...imageExportingMap.value,
      [image.id]: true,
    }
    uploadCenterStore.clearBatchError(batchId)
    uploadCenterStore.registerBatchController(batchId, controller)

    try {
      if (task) {
        uploadCenterStore.updateTask(task.id, {
          loaded: 0,
          progress: 0,
          status: 'downloading',
          total: estimatedTotal,
        })
      }

      const blob = await queueDockerRequest(() =>
        dockerApi.exportImage(
          connectionId,
          image.id,
          imageRef,
          (progressEvent) => {
            if (!task) {
              return
            }

            const total = progressEvent.total ?? estimatedTotal
            const loaded = total > 0 ? Math.min(progressEvent.loaded, total) : progressEvent.loaded
            uploadCenterStore.updateTask(task.id, {
              loaded,
              progress: total > 0 ? Math.min(100, Math.round((loaded / total) * 100)) : 0,
              total,
            })
          },
          controller.signal,
        ),
      )
      const url = window.URL.createObjectURL(blob)
      const anchor = document.createElement('a')
      anchor.href = url
      anchor.download = filename
      anchor.click()
      window.URL.revokeObjectURL(url)
      if (task) {
        uploadCenterStore.updateTask(task.id, {
          loaded: blob.size,
          progress: 100,
          status: 'success',
          total: blob.size,
        })
      }
      getUiApi().message.success(`镜像 ${imageRef} 导出完成。`)
    } catch (error) {
      if (uploadCenterStore.isBatchCancelled(batchId)) {
        return
      }

      if (task) {
        uploadCenterStore.updateTask(task.id, {
          status: 'error',
        })
      }
      uploadCenterStore.markBatchError(
        batchId,
        error instanceof Error ? error.message : '镜像导出失败。',
      )
      console.error('Failed to export image', error)
      getUiApi().message.error(error instanceof Error ? error.message : '镜像导出失败。')
    } finally {
      uploadCenterStore.clearBatchController(batchId)
      imageExportingMap.value = {
        ...imageExportingMap.value,
        [image.id]: false,
      }
    }
  }

  async function submitTagImage() {
    if (!imageTagSource.value.trim() || !imageTagTarget.value.trim()) {
      getUiApi().message.error('源镜像和目标标签都不能为空。')
      return
    }

    imageTagging.value = true
    try {
      const connectionId = requireConnectionId()
      await queueDockerRequest(() =>
        dockerApi.tagImage(connectionId, imageTagSource.value.trim(), imageTagTarget.value.trim()),
      )
      imageTagVisible.value = false
      getUiApi().message.success('镜像重新打标签成功。')
      await refreshTabsAfterChange('images')
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
      imageHistoryItems.value = await queueDockerRequest(() =>
        dockerApi.getImageHistory(connectionId, image.id),
      )
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
      imageRefsItems.value = await queueDockerRequest(() =>
        dockerApi.getImageContainers(connectionId, image.id),
      )
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
      await refreshTabsAfterChange('images')
    } catch (error) {
      console.error('Failed to pull image', error)
      getUiApi().message.error(error instanceof Error ? error.message : '拉取镜像失败。')
    } finally {
      pullingImage.value = false
    }
  }

  async function importImage(file: File) {
    const connectionId = requireConnectionId()
    importingImage.value = true
    const batchId = uploadCenterStore.createBatch(
      connectionId,
      'Docker 镜像导入',
      [{ file, name: file.name, path: 'Docker 镜像' }],
      'docker-image-import',
    )
    const task = uploadCenterStore.batches.find((item) => item.id === batchId)?.tasks[0]
    const controller = new AbortController()
    uploadCenterStore.clearBatchError(batchId)
    uploadCenterStore.registerBatchController(batchId, controller)

    try {
      if (task) {
        uploadCenterStore.updateTask(task.id, {
          loaded: 0,
          progress: 0,
          status: 'uploading',
          total: file.size,
        })
      }

      const formData = new FormData()
      formData.append('file', file, file.name)
      await queueDockerRequest(() =>
        dockerApi.importImage(
          connectionId,
          formData,
          (progressEvent) => {
            if (!task) {
              return
            }

            const total = progressEvent.total ?? file.size
            const loaded = Math.min(progressEvent.loaded, total)
            uploadCenterStore.updateTask(task.id, {
              loaded,
              progress: total > 0 ? Math.min(100, Math.round((loaded / total) * 100)) : 0,
              total,
            })
          },
          controller.signal,
        ),
      )
      if (task) {
        uploadCenterStore.updateTask(task.id, {
          loaded: file.size,
          progress: 100,
          status: 'success',
          total: file.size,
        })
      }
      getUiApi().message.success(`镜像归档 ${file.name} 导入完成。`)
      await refreshTabsAfterChange('images')
    } catch (error) {
      if (uploadCenterStore.isBatchCancelled(batchId)) {
        return
      }

      if (task) {
        uploadCenterStore.updateTask(task.id, {
          status: 'error',
        })
      }
      uploadCenterStore.markBatchError(
        batchId,
        error instanceof Error ? error.message : '镜像导入失败。',
      )
      console.error('Failed to import image', error)
      getUiApi().message.error(error instanceof Error ? error.message : '镜像导入失败。')
    } finally {
      uploadCenterStore.clearBatchController(batchId)
      importingImage.value = false
    }
  }

  async function handleComposeProjectAction(
    project: DockerComposeProject,
    action: 'up' | 'stop' | 'restart' | 'down',
  ) {
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

      await refreshTabsAfterChange('containers', 'compose')
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

  function confirmComposeProjectAction(
    project: DockerComposeProject,
    action: 'up' | 'stop' | 'restart' | 'down',
  ) {
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

  function openComposeServices(project: DockerComposeProject) {
    try {
      const connectionId = requireConnectionId()
      const payload = getComposeProjectPayload(project)
      if (!payload) {
        getUiApi().message.warning('该编排项目缺少 compose 配置文件路径，无法加载服务。')
        return
      }

      desktopStore.openWindow('docker-compose-services', {
        connectionId,
        host: props.host ?? sshStore.host,
        project,
        title: `编排服务 · ${project.name}`,
        username: props.username ?? sshStore.username,
      })
    } catch (error) {
      console.error('Failed to open compose services window', error)
      getUiApi().message.error(error instanceof Error ? error.message : '打开编排服务窗口失败。')
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

    composeProjects.value = await queueDockerRequest(() =>
      dockerApi.listComposeProjects(connectionId),
    )
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
      const services = await queueDockerRequest(() =>
        dockerApi.listComposeServices(connectionId, payload),
      )
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
      const result = await queueDockerRequest(() =>
        dockerApi.batchStartContainers(connectionId, selectedStoppedIds.value),
      )
      getUiApi().message.success(`批量启动完成，共处理 ${result.processed} 个容器。`)
      await refreshTabsAfterChange('containers')
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
      const result = await queueDockerRequest(() =>
        dockerApi.batchStopContainers(connectionId, selectedRunningIds.value),
      )
      getUiApi().message.success(`批量停止完成，共处理 ${result.processed} 个容器。`)
      await refreshTabsAfterChange('containers')
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
      await refreshTabsAfterChange('containers')
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
      await refreshTabsAfterChange('images')
    } catch (error) {
      console.error('Failed to prune images', error)
      getUiApi().message.error(error instanceof Error ? error.message : '镜像清理失败。')
    }
  }

  async function createNetwork(payload: DockerCreateNetworkPayload) {
    try {
      const connectionId = requireConnectionId()
      const result = await queueDockerRequest(() => dockerApi.createNetwork(connectionId, payload))
      getUiApi().message.success(
        result.warning ? `网络已创建，返回警告：${result.warning}` : 'Docker 网络创建成功。',
      )
      await refreshTabsAfterChange('networks')
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
      getUiApi().message.success(
        result.warning ? `存储卷已创建，返回警告：${result.warning}` : 'Docker 存储卷创建成功。',
      )
      await refreshTabsAfterChange('volumes')
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
      inspectContent.value = await queueDockerRequest(() =>
        dockerApi.inspectNetwork(connectionId, network.id),
      )
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
      inspectContent.value = await queueDockerRequest(() =>
        dockerApi.inspectVolume(connectionId, volume.name),
      )
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
      await refreshTabsAfterChange('networks')
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
      await refreshTabsAfterChange('volumes')
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

  async function updateNetworkConnection(
    network: DockerNetwork,
    container: string,
    disconnect = false,
    force = false,
  ) {
    try {
      const connectionId = requireConnectionId()
      const trimmedContainer = container.trim()
      if (!trimmedContainer) {
        getUiApi().message.warning('请输入容器 ID 或容器名称。')
        return false
      }

      if (disconnect) {
        await queueDockerRequest(() =>
          dockerApi.disconnectNetwork(connectionId, network.id, {
            container: trimmedContainer,
            force,
          }),
        )
        getUiApi().message.success(`已将容器 ${trimmedContainer} 从网络 ${network.name} 断开。`)
      } else {
        await queueDockerRequest(() =>
          dockerApi.connectNetwork(connectionId, network.id, { container: trimmedContainer }),
        )
        getUiApi().message.success(`已将容器 ${trimmedContainer} 连接到网络 ${network.name}。`)
      }

      await refreshTabsAfterChange('networks')
      return true
    } catch (error) {
      console.error('Failed to update network connection', error)
      getUiApi().message.error(
        error instanceof Error ? error.message : '更新 Docker 网络连接失败。',
      )
      return false
    }
  }

  async function pruneNetworks() {
    try {
      const connectionId = requireConnectionId()
      const result = await queueDockerRequest(() => dockerApi.pruneNetworks(connectionId))
      getUiApi().message.success(`网络清理完成，共删除 ${result.deletedCount} 个未使用网络。`)
      await refreshTabsAfterChange('networks')
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
      await refreshTabsAfterChange('volumes')
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

    void refreshTabsAfterChange('containers')
  }

  function handleComposeCreated(event: Event) {
    const detail = (event as CustomEvent<{ connectionId?: string; project?: DockerComposeProject }>)
      .detail
    if (detail?.connectionId && detail.connectionId !== activeConnectionId.value) {
      return
    }

    if (detail?.project) {
      const nextProjects = composeProjects.value.filter(
        (project) => project.name !== detail.project?.name,
      )
      composeProjects.value = [detail.project, ...nextProjects]
      selectedComposeProjectName.value = detail.project.name
      composeAvailable.value = true
    }

    void refreshTabsAfterChange('compose')
  }

  onMounted(() => {
    void loadTabData(activeTab.value)
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
    await loadDockerSection(
      () => loadContainersPage(1, containerPageSize.value),
      '加载容器列表失败。',
    )
  })

  watch(containerSearchKeyword, async () => {
    selectedContainerIds.value = []
    await loadDockerSection(
      () => loadContainersPage(1, containerPageSize.value),
      '加载容器列表失败。',
    )
  })

  watch(imageSearchKeyword, async () => {
    await loadDockerSection(() => loadImagesPage(1, imagePageSize.value), '加载镜像列表失败。')
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
    composeSearchKeyword,
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
    containerSearchKeyword,
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
    filteredComposeProjects,
    filteredNetworks,
    filteredVolumes,
    exportImage,
    getComposeConfigFiles,
    getComposeServiceStatusType,
    getComposeStatusType,
    getContainerPortUrl,
    handleContainerAdvancedAction,
    handleContainerPageChange,
    handleContainerPageSizeChange,
    handleImagePageChange,
    handleImagePageSizeChange,
    imageExportingMap,
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
    importImage,
    importingImage,
    images,
    imageSearchKeyword,
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
    networkSearchKeyword,
    networks,
    openComposeServices,
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
    refreshActiveTab,
    refreshCompose,
    refreshContainers,
    refreshImages,
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
    setContainerSearchKeyword,
    setContainerStatusFilter,
    setImageSearchKeyword,
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
    volumeSearchKeyword,
    volumes,
  }
}

export type DockerViewController = UnwrapNestedRefs<ReturnType<typeof useDockerView>>

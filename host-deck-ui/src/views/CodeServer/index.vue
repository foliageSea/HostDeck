<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import {
  ChevronDown,
  ChevronRight,
  ExternalLink,
  FolderOpen,
  HardDrive,
  Package,
  Play,
  Power,
  RefreshCw,
  Server,
  Trash2,
  TriangleAlert,
  Upload,
  ZoomIn,
  ZoomOut,
} from '@lucide/vue'
import {
  codeServerApi,
  uploadPackage,
  type CodeServerArch,
  type CodeServerPackage,
  type CodeServerPreflight,
  type CodeServerSession,
  type CodeServerSessionState,
  type CodeServerTargetStatus,
} from '@/api/code-server'
import { getUiApi } from '@/lib/ui'
import { useDesktopStore } from '@/stores/desktop'
import { useSettingsStore } from '@/stores/settings'
import { useSshStore } from '@/stores/ssh'

const props = defineProps<{
  path?: string
  windowId?: string
  /** 由窗口标题栏的开关写入窗口 props。 */
  toolbarCollapsed?: boolean
}>()

const desktopStore = useDesktopStore()
const settingsStore = useSettingsStore()
const sshStore = useSshStore()

const loading = ref(true)
const refreshing = ref(false)
const fatalError = ref('')
const actionError = ref('')
const status = ref<CodeServerTargetStatus | null>(null)
const packages = ref<CodeServerPackage[]>([])
const packagesLoading = ref(false)
const packagesVisible = ref(false)
const deletingId = ref<string | null>(null)
const installing = ref(false)
const starting = ref(false)
const stopping = ref(false)
const uninstalling = ref(false)
const frameKey = ref(0)
const frameLoaded = ref(false)
const localHeaderCollapsed = ref(false)
// 收起状态存在窗口 props 中，标题栏按钮和视图共用同一份状态。
const headerCollapsed = computed({
  get: () => (props.windowId ? Boolean(props.toolbarCollapsed) : localHeaderCollapsed.value),
  set: (value: boolean) => {
    if (props.windowId) {
      desktopStore.updateWindowProps(props.windowId, { toolbarCollapsed: value })
    } else {
      localHeaderCollapsed.value = value
    }
  },
})

const FRAME_ZOOM_STORAGE_KEY = 'host-deck:code-server:frame-zoom'
const FRAME_ZOOM_MIN = 0.5
const FRAME_ZOOM_MAX = 2
const FRAME_ZOOM_STEP = 0.1
const frameZoom = ref(loadFrameZoom())
const frameZoomPercent = computed(() => Math.round(frameZoom.value * 100))
// transform 缩放后用反比宽高铺满容器，避免出现空白或滚动条。
const frameStyle = computed(() => {
  const zoom = frameZoom.value
  if (zoom === 1) return undefined
  return {
    width: `${100 / zoom}%`,
    height: `${100 / zoom}%`,
    transform: `scale(${zoom})`,
    transformOrigin: '0 0',
  }
})

const showUpload = ref(false)
const pendingFile = ref<File | null>(null)
const fileInput = ref<HTMLInputElement | null>(null)
const uploadVersion = ref('')
const uploadArch = ref<CodeServerArch>('amd64')
const uploading = ref(false)
const uploadLoaded = ref(0)
const uploadTotal = ref(0)
const selectedPackageId = ref<string | null>(null)

const packageNamePattern = /code-server-([0-9][^/]*?)-linux-(amd64|arm64)\.(?:tar\.gz|tgz)$/i
const archOptions = [
  { label: 'linux-amd64（x86_64）', value: 'amd64' },
  { label: 'linux-arm64（aarch64）', value: 'arm64' },
]

const sessionStateLabels: Record<CodeServerSessionState, string> = {
  installing: '安装中',
  starting: '启动中',
  running: '运行中',
  stopping: '停止中',
  stopped: '已停止',
  error: '异常',
}

type TagType = 'default' | 'success' | 'warning' | 'error' | 'info'

let pollTimer: number | null = null
let statusRequestSeq = 0
let isUnmounted = false

const hasConnection = computed(() => Boolean(sshStore.connectionId && sshStore.isConnected))
const connectionText = computed(() => {
  if (!hasConnection.value) return '未连接 SSH'
  return sshStore.username + '@' + sshStore.host + ':' + String(sshStore.port ?? '')
})
const preflight = computed<CodeServerPreflight | null>(() => status.value?.preflight ?? null)
const session = computed<CodeServerSession | null>(() => status.value?.session ?? null)
const issues = computed(() => preflight.value?.issues ?? [])
const preflightError = computed(() => status.value?.preflightError ?? '')
const supported = computed(() => {
  if (preflightError.value) return false
  return preflight.value?.supported ?? true
})
const installedVersion = computed(() => preflight.value?.installedVersion ?? null)
const targetArch = computed<CodeServerArch>(() => {
  const arch = preflight.value?.arch ?? ''
  return arch === 'aarch64' || arch === 'arm64' ? 'arm64' : 'amd64'
})
const archDetected = computed(() => preflight.value?.arch || '未知')
const CODE_SERVER_FALLBACK_VERSION = '4.143.1'
const codeServerReleasesUrl = 'https://github.com/coder/code-server/releases'
const downloadVersion = computed(
  () => matchingPackages.value[0]?.version || CODE_SERVER_FALLBACK_VERSION,
)
const downloadUrl = computed(
  () =>
    'https://github.com/coder/code-server/releases/download/v' +
    downloadVersion.value +
    '/code-server-' +
    downloadVersion.value +
    '-linux-' +
    targetArch.value +
    '.tar.gz',
)

const folderText = computed(() => props.path?.trim() || '目标用户主目录')
const matchingPackages = computed(() =>
  packages.value.filter((item) => item.arch === targetArch.value),
)
const packageOptions = computed(() =>
  matchingPackages.value.map((item) => ({
    label: 'v' + item.version + ' · ' + formatBytes(item.size),
    value: item.id,
  })),
)
const selectedPackage = computed(
  () => matchingPackages.value.find((item) => item.id === selectedPackageId.value) ?? null,
)
const sessionState = computed<CodeServerSessionState | null>(() =>
  stopping.value ? 'stopping' : session.value?.state ?? null,
)
const sessionLabel = computed(() =>
  sessionState.value ? sessionStateLabels[sessionState.value] : '',
)
const sessionTagType = computed<TagType>(() => {
  switch (sessionState.value) {
    case 'running':
      return 'success'
    case 'installing':
    case 'starting':
    case 'stopping':
      return 'warning'
    case 'error':
      return 'error'
    default:
      return 'default'
  }
})
const isRunning = computed(
  () => !stopping.value && sessionState.value === 'running' && Boolean(session.value?.url),
)

watch(isRunning, (running) => {
  // 启动进入运行态后默认收起顶部操作区；手动展开后不会被状态刷新重新收起。
  headerCollapsed.value = running
})
const isWorking = computed(
  () =>
    installing.value ||
    starting.value ||
    stopping.value ||
    uninstalling.value ||
    sessionState.value === 'installing' ||
    sessionState.value === 'starting' ||
    sessionState.value === 'stopping',
)
const canStop = computed(
  () => Boolean(session.value) && sessionState.value !== 'stopped' && !stopping.value,
)
const sessionProgressPercent = computed<number | null>(() => {
  const progress = session.value?.progress
  if (typeof progress !== 'number' || !Number.isFinite(progress)) return null
  const percent = progress <= 1 ? progress * 100 : progress
  return Math.max(0, Math.min(100, Math.round(percent)))
})
const uploadPercent = computed(() => {
  if (uploadTotal.value <= 0) return 0
  return Math.max(0, Math.min(100, Math.round((uploadLoaded.value / uploadTotal.value) * 100)))
})
const ideUrl = computed(() => {
  const rawUrl = session.value?.url
  if (!rawUrl) return ''
  let base = rawUrl
  if (!base.includes('?') && !base.endsWith('/')) base += '/'
  const folder = props.path?.trim()
  if (!folder || base.includes('folder=')) return base
  return base + (base.includes('?') ? '&' : '?') + 'folder=' + encodeURIComponent(folder)
})

function formatBytes(bytes: number | null | undefined): string {
  if (bytes === null || bytes === undefined) return '未知'
  if (bytes < 1024) return String(bytes) + ' B'
  const units = ['KB', 'MB', 'GB', 'TB']
  let value = bytes / 1024
  let index = 0
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024
    index += 1
  }
  return value.toFixed(value >= 100 ? 0 : 1) + ' ' + units[index]
}

function formatTimestamp(value: string | null | undefined): string {
  if (!value) return '未知'
  const parsed = new Date(value)
  if (Number.isNaN(parsed.getTime())) return value
  return new Intl.DateTimeFormat('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(parsed)
}

function errorMessage(error: unknown, fallback: string): string {
  if (error instanceof Error && error.message) return error.message
  return fallback
}

function shouldPoll(): boolean {
  return (
    installing.value ||
    starting.value ||
    stopping.value ||
    uninstalling.value ||
    sessionState.value === 'installing' ||
    sessionState.value === 'starting' ||
    sessionState.value === 'stopping'
  )
}

function syncPolling() {
  if (shouldPoll()) {
    if (pollTimer === null) {
      pollTimer = window.setInterval(() => {
        void fetchStatus({ silent: true })
      }, 1000)
    }
    return
  }

  if (pollTimer !== null) {
    window.clearInterval(pollTimer)
    pollTimer = null
  }
}

function selectPackage() {
  const candidates = matchingPackages.value
  if (!candidates.length) {
    selectedPackageId.value = null
    return
  }

  if (selectedPackageId.value && candidates.some((item) => item.id === selectedPackageId.value)) {
    return
  }

  const installed = installedVersion.value
  const preferred = installed ? candidates.find((item) => item.version === installed) : undefined
  selectedPackageId.value = (preferred ?? candidates[0]).id
}

function maybeRevealUpload() {
  if (!preflight.value) return
  if (!installedVersion.value && matchingPackages.value.length === 0) {
    showUpload.value = true
  }
}

async function fetchStatus(options: { silent?: boolean } = {}) {
  const connectionId = sshStore.connectionId
  if (!connectionId) {
    status.value = null
    loading.value = false
    syncPolling()
    return
  }

  const requestSeq = ++statusRequestSeq
  if (!options.silent) refreshing.value = true

  try {
    const nextStatus = await codeServerApi.status(connectionId)
    if (requestSeq !== statusRequestSeq || isUnmounted) return
    status.value = nextStatus
    fatalError.value = ''
    selectPackage()
    maybeRevealUpload()
  } catch (error) {
    if (requestSeq !== statusRequestSeq || isUnmounted) return
    if (!options.silent) fatalError.value = errorMessage(error, '加载 IDE 状态失败。')
  } finally {
    if (requestSeq === statusRequestSeq) {
      if (!options.silent) refreshing.value = false
      loading.value = false
      syncPolling()
    }
  }
}

async function fetchPackages(silent = false) {
  if (!silent) packagesLoading.value = true
  try {
    packages.value = await codeServerApi.listPackages()
    selectPackage()
    maybeRevealUpload()
  } catch (error) {
    if (!silent) getUiApi().message.error(errorMessage(error, '加载离线包列表失败。'))
  } finally {
    if (!silent) packagesLoading.value = false
  }
}

async function copyDownloadUrl() {
  try {
    await navigator.clipboard.writeText(downloadUrl.value)
    getUiApi().message.success('下载地址已复制。')
  } catch {
    getUiApi().message.error('复制失败，请手动选择地址复制。')
  }
}

function refreshStatus() {
  void fetchStatus()
  void fetchPackages(true)
}

async function installSelected() {
  const connectionId = sshStore.connectionId
  const pkg = selectedPackage.value
  if (!connectionId || !pkg || installing.value) return

  installing.value = true
  actionError.value = ''
  syncPolling()
  try {
    await codeServerApi.install(connectionId, pkg.id)
    getUiApi().message.success('已安装 code-server ' + pkg.version + '。')
    await fetchStatus({ silent: true })
  } catch (error) {
    actionError.value = errorMessage(error, '安装离线包失败。')
  } finally {
    installing.value = false
    syncPolling()
  }
}

async function startIde() {
  const connectionId = sshStore.connectionId
  if (!connectionId || starting.value) return

  starting.value = true
  actionError.value = ''
  syncPolling()
  try {
    const folder = props.path?.trim()
    await codeServerApi.start(connectionId, folder || undefined)
    await fetchStatus({ silent: true })
  } catch (error) {
    actionError.value = errorMessage(error, '启动 IDE 失败。')
  } finally {
    starting.value = false
    syncPolling()
  }
}

async function stopIde() {
  const connectionId = sshStore.connectionId
  if (!connectionId || stopping.value) return

  stopping.value = true
  frameLoaded.value = false
  actionError.value = ''
  syncPolling()
  try {
    await nextTick()
    const stoppedSession = await codeServerApi.stop(connectionId)
    if (connectionId !== sshStore.connectionId || isUnmounted) return

    // 停止结果直接驱动 iframe 卸载，旧状态请求不能恢复已停止的会话。
    statusRequestSeq += 1
    refreshing.value = false
    if (status.value) status.value = { ...status.value, session: stoppedSession }
    frameLoaded.value = false
    await fetchStatus({ silent: true })
  } catch (error) {
    actionError.value = errorMessage(error, '停止 IDE 失败。')
  } finally {
    stopping.value = false
    syncPolling()
  }
}

function confirmUninstall() {
  const connectionId = sshStore.connectionId
  if (!connectionId || !hasConnection.value || isWorking.value || isUnmounted) return

  getUiApi().dialog.warning({
    title: '卸载在线 IDE',
    content:
      '将停止 ' +
      connectionText.value +
      ' 上的 IDE 会话，并移除 HostDeck 安装的所有 code-server 版本。项目文件、用户设置和扩展会保留，HostDeck 中的离线包也会保留。',
    positiveText: '卸载 IDE',
    negativeText: '取消',
    onPositiveClick: async () => {
      if (
        connectionId !== sshStore.connectionId ||
        !hasConnection.value ||
        isWorking.value ||
        isUnmounted
      ) {
        getUiApi().message.warning('连接或 IDE 状态已变化，请重新确认卸载。')
        return
      }

      uninstalling.value = true
      actionError.value = ''
      syncPolling()
      try {
        await codeServerApi.uninstall(connectionId)
        if (connectionId === sshStore.connectionId && !isUnmounted) {
          // 使卸载前发出的状态请求失效，立即移除失效的 iframe。
          statusRequestSeq += 1
          status.value = null
          frameLoaded.value = false
          frameKey.value += 1
          headerCollapsed.value = false
        }
        getUiApi().message.success('在线 IDE 已卸载，项目、设置和扩展已保留。')
      } catch (error) {
        const message = errorMessage(error, '卸载 IDE 失败。')
        if (connectionId === sshStore.connectionId && !isUnmounted) actionError.value = message
        getUiApi().message.error(message)
      } finally {
        if (connectionId === sshStore.connectionId && !isUnmounted) await fetchStatus()
        uninstalling.value = false
        if (!isUnmounted) syncPolling()
      }
    },
  })
}

function refreshFrame() {
  frameLoaded.value = false
  frameKey.value += 1
}

function clampFrameZoom(value: number) {
  const rounded = Math.round(value * 10) / 10
  return Math.min(FRAME_ZOOM_MAX, Math.max(FRAME_ZOOM_MIN, rounded))
}

function loadFrameZoom() {
  try {
    const stored = Number(window.localStorage.getItem(FRAME_ZOOM_STORAGE_KEY))
    return Number.isFinite(stored) && stored > 0 ? clampFrameZoom(stored) : 1
  } catch {
    return 1
  }
}

function setFrameZoom(value: number) {
  frameZoom.value = clampFrameZoom(value)
  try {
    window.localStorage.setItem(FRAME_ZOOM_STORAGE_KEY, String(frameZoom.value))
  } catch {
    // 存储不可用时仅本次生效。
  }
}

function zoomFrameIn() {
  setFrameZoom(frameZoom.value + FRAME_ZOOM_STEP)
}

function zoomFrameOut() {
  setFrameZoom(frameZoom.value - FRAME_ZOOM_STEP)
}

function resetFrameZoom() {
  setFrameZoom(1)
}

function refreshTop() {
  if (isRunning.value) {
    refreshFrame()
    return
  }
  void refreshStatus()
}

function openIdeTab() {
  if (!ideUrl.value) return
  const target = new URL(ideUrl.value, window.location.href)
  window.open(target.href, '_blank', 'noopener,noreferrer')
}

function openIdeDirectory(kind: 'installRoot' | 'dataRoot') {
  const connectionId = sshStore.connectionId
  const path = preflight.value?.[kind]
  if (!hasConnection.value || !connectionId || !path) return

  try {
    desktopStore.openWindow('files', {
      connectionId,
      host: sshStore.host,
      port: sshStore.port,
      username: sshStore.username,
      path,
      title: kind === 'installRoot' ? 'IDE 安装目录' : 'IDE 数据目录',
    })
  } catch (error) {
    getUiApi().message.error(errorMessage(error, '打开 IDE 目录失败。'))
  }
}

async function scanPackages() {
  if (packagesLoading.value) return
  packagesLoading.value = true
  try {
    await codeServerApi.scanPackages()
    await fetchPackages(true)
    getUiApi().message.success('已扫描离线包目录。')
  } catch (error) {
    getUiApi().message.error(errorMessage(error, '扫描离线包目录失败。'))
  } finally {
    packagesLoading.value = false
  }
}

async function deletePackage(pkg: CodeServerPackage) {
  if (deletingId.value) return
  deletingId.value = pkg.id
  try {
    await codeServerApi.deletePackage(pkg.id)
    packages.value = packages.value.filter((item) => item.id !== pkg.id)
    if (selectedPackageId.value === pkg.id) selectedPackageId.value = null
    selectPackage()
    getUiApi().message.success('已删除离线包 ' + pkg.version + '。')
  } catch (error) {
    getUiApi().message.error(errorMessage(error, '删除离线包失败。'))
  } finally {
    deletingId.value = null
  }
}

function openUploadPanel() {
  packagesVisible.value = false
  showUpload.value = true
}

function pickFile() {
  fileInput.value?.click()
}

function handleFileChange(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0] ?? null
  pendingFile.value = file
  input.value = ''

  if (!file) return

  const matched = packageNamePattern.exec(file.name)
  if (matched) {
    uploadVersion.value = matched[1]
    uploadArch.value = matched[2].toLowerCase() === 'arm64' ? 'arm64' : 'amd64'
    return
  }

  getUiApi().message.warning('无法从文件名解析版本与架构，请手动填写。')
}

async function submitUpload() {
  const file = pendingFile.value
  const version = uploadVersion.value.trim()
  if (!file || uploading.value) return
  if (!version) {
    getUiApi().message.warning('请填写 code-server 版本号。')
    return
  }
  if (!/^\d+\.\d+\.\d+$/.test(version)) {
    getUiApi().message.warning('版本号格式应为 x.y.z，例如 4.143.1。')
    return
  }

  uploading.value = true
  actionError.value = ''
  uploadLoaded.value = 0
  uploadTotal.value = file.size

  try {
    const uploaded = await uploadPackage(file, {
      version,
      arch: uploadArch.value,
      onProgress: (loaded, total) => {
        uploadLoaded.value = loaded
        uploadTotal.value = total
      },
    })
    getUiApi().message.success('离线包 v' + uploaded.version + '（' + uploaded.arch + '）已上传。')
    pendingFile.value = null
    uploadVersion.value = ''
    uploadLoaded.value = 0
    uploadTotal.value = 0
    await fetchPackages(true)
    selectedPackageId.value = uploaded.id
    selectPackage()
  } catch (error) {
    actionError.value = errorMessage(error, '上传离线包失败。')
  } finally {
    uploading.value = false
  }
}

onMounted(() => {
  if (!hasConnection.value) {
    loading.value = false
    return
  }

  void fetchPackages()
  void fetchStatus()
})

onBeforeUnmount(() => {
  isUnmounted = true
  if (pollTimer !== null) {
    window.clearInterval(pollTimer)
    pollTimer = null
  }
})

watch(
  () => sshStore.connectionId,
  (nextConnectionId, previousConnectionId) => {
    if (nextConnectionId === previousConnectionId) return

    status.value = null
    fatalError.value = ''
    actionError.value = ''
    frameLoaded.value = false
    loading.value = Boolean(nextConnectionId)
    if (!nextConnectionId) {
      syncPolling()
      return
    }

    void fetchPackages()
    void fetchStatus()
  },
)

watch(
  () => props.path,
  () => {
    if (isRunning.value) refreshFrame()
  },
)
</script>

<template>
  <div class="code-server-view" :class="{ 'code-server-dark': settingsStore.isDark }">
    <header v-if="!headerCollapsed" class="cs-toolbar">
      <div class="cs-target">
        <Server :size="16" aria-hidden="true" />
        <span class="cs-target-text" :title="connectionText">{{ connectionText }}</span>
        <NTag v-if="sessionLabel" size="small" :type="sessionTagType" :bordered="false">
          {{ sessionLabel }}
        </NTag>
        <span v-if="isRunning" class="cs-folder" :title="folderText">
          <FolderOpen :size="13" aria-hidden="true" />
          <span class="cs-folder-text">{{ folderText }}</span>
        </span>
      </div>
      <div class="cs-actions">
        <div v-if="isRunning" class="cs-zoom" role="group" aria-label="IDE 缩放">
          <NButton
            size="small"
            quaternary
            :disabled="frameZoom <= FRAME_ZOOM_MIN"
            title="缩小"
            aria-label="缩小"
            @click="zoomFrameOut"
          >
            <template #icon><ZoomOut :size="15" /></template>
          </NButton>
          <button
            type="button"
            class="cs-zoom-value"
            title="重置为 100%"
            aria-label="重置缩放"
            @click="resetFrameZoom"
          >
            {{ frameZoomPercent }}%
          </button>
          <NButton
            size="small"
            quaternary
            :disabled="frameZoom >= FRAME_ZOOM_MAX"
            title="放大"
            aria-label="放大"
            @click="zoomFrameIn"
          >
            <template #icon><ZoomIn :size="15" /></template>
          </NButton>
        </div>
        <NButton size="small" quaternary :loading="!isRunning && refreshing" @click="refreshTop">
          <template #icon><RefreshCw :size="15" /></template>
          {{ isRunning ? '刷新' : '刷新状态' }}
        </NButton>
        <NButton v-if="isRunning" size="small" quaternary @click="openIdeTab">
          <template #icon><ExternalLink :size="15" /></template>
          新标签页
        </NButton>
        <NButton size="small" quaternary @click="packagesVisible = true">
          <template #icon><Package :size="15" /></template>
          离线包 {{ packages.length }}
        </NButton>
        <NButton
          size="small"
          quaternary
          :disabled="!hasConnection || !preflight?.installRoot"
          :title="preflight?.installRoot || ''"
          @click="openIdeDirectory('installRoot')"
        >
          <template #icon><FolderOpen :size="15" /></template>
          打开安装目录
        </NButton>
        <NButton
          size="small"
          quaternary
          :disabled="!hasConnection || !preflight?.dataRoot"
          :title="preflight?.dataRoot || ''"
          @click="openIdeDirectory('dataRoot')"
        >
          <template #icon><FolderOpen :size="15" /></template>
          打开数据目录
        </NButton>
        <NButton
          v-if="canStop"
          size="small"
          type="error"
          secondary
          :loading="stopping"
          :disabled="uninstalling"
          @click="stopIde"
        >
          <template #icon><Power :size="15" /></template>
          停止
        </NButton>
      </div>
    </header>

    <div v-if="!hasConnection" class="cs-center">
      <NEmpty description="未连接 SSH，无法打开远端 IDE">
        <template #extra>
          <span class="cs-muted">请先在主界面连接一台 Linux 主机。</span>
        </template>
      </NEmpty>
    </div>

    <div v-else class="cs-body">
      <div v-if="loading" class="cs-center">
        <NSpin size="medium" />
      </div>

      <div v-else-if="stopping" class="cs-center" role="status" aria-live="polite" aria-busy="true">
        <div class="cs-stopping">
          <NSpin size="medium" />
          <span>正在停止 IDE…</span>
        </div>
      </div>

      <div v-else-if="isRunning" class="cs-running">
        <div class="cs-frame-wrap">
          <div v-if="!frameLoaded" class="cs-frame-loading">
            <NSpin size="small" />
            <span>正在载入 IDE…</span>
          </div>
          <iframe
            :key="frameKey"
            class="cs-frame"
            :class="{ 'cs-frame-ready': frameLoaded }"
            :style="frameStyle"
            :src="ideUrl"
            title="code-server IDE"
            allow="clipboard-read; clipboard-write; fullscreen"
            @load="frameLoaded = true"
          />
        </div>
      </div>

      <div v-else class="cs-setup">
        <NAlert v-if="fatalError" type="error" title="无法加载 IDE 状态">
          {{ fatalError }}
        </NAlert>
        <NAlert v-if="actionError" type="error" closable @close="actionError = ''">
          {{ actionError }}
        </NAlert>
        <NAlert v-if="preflightError" type="warning" title="目标机检查失败">
          {{ preflightError }}
        </NAlert>
        <NAlert v-if="issues.length" type="warning" title="目标机不满足运行条件">
          <ul class="cs-issue-list">
            <li v-for="issue in issues" :key="issue">{{ issue }}</li>
          </ul>
        </NAlert>
        <NAlert v-if="session?.error" type="error" title="IDE 会话异常">
          {{ session.error }}
        </NAlert>

        <section class="cs-card">
          <header class="cs-card-header">
            <HardDrive :size="15" aria-hidden="true" />
            <h2>目标环境</h2>
          </header>
          <dl class="cs-facts">
            <div>
              <dt>架构</dt>
              <dd>{{ archDetected }}（{{ targetArch }}）</dd>
            </div>
            <div>
              <dt>glibc</dt>
              <dd>{{ preflight?.libc || '未知' }}</dd>
            </div>
            <div>
              <dt>磁盘可用</dt>
              <dd>{{ formatBytes(preflight?.diskFreeBytes) }}</dd>
            </div>
            <div>
              <dt>已安装版本</dt>
              <dd>{{ installedVersion ? 'v' + installedVersion : '未安装' }}</dd>
            </div>
          </dl>
        </section>

        <section v-if="!installedVersion" class="cs-card">
          <header class="cs-card-header">
            <Package :size="15" aria-hidden="true" />
            <h2>安装 IDE</h2>
          </header>
          <p class="cs-muted">通过 SSH 将离线包推送到目标机安装，无需目标机联网。</p>
          <div v-if="matchingPackages.length" class="cs-row">
            <NSelect
              v-model:value="selectedPackageId"
              class="cs-grow"
              :options="packageOptions"
              placeholder="选择与目标架构匹配的离线包"
            />
            <NButton
              type="primary"
              :loading="installing"
              :disabled="!selectedPackage || !supported || isWorking"
              @click="installSelected"
            >
              <template #icon><Play :size="15" /></template>
              安装
            </NButton>
          </div>
          <div v-else class="cs-empty-row">
            <TriangleAlert :size="15" aria-hidden="true" />
            <span>当前架构（{{ targetArch }}）暂无离线包。</span>
            <NButton size="small" type="primary" @click="showUpload = true">上传离线包</NButton>
          </div>
        </section>

        <section v-else class="cs-card">
          <header class="cs-card-header">
            <Play :size="15" aria-hidden="true" />
            <h2>启动 IDE</h2>
          </header>
          <p class="cs-muted">将以 {{ folderText }} 作为工作区打开。</p>
          <div class="cs-row cs-row-between">
            <span class="cs-installed">已安装 v{{ installedVersion }}</span>
            <div class="cs-row">
              <NButton
                type="error"
                quaternary
                :loading="uninstalling"
                :disabled="!hasConnection || isWorking"
                @click="confirmUninstall"
              >
                <template #icon><Trash2 :size="15" /></template>
                卸载 IDE
              </NButton>
              <NButton
                type="primary"
                :loading="starting"
                :disabled="!supported || isWorking"
                @click="startIde"
              >
                <template #icon><Play :size="15" /></template>
                启动 IDE
              </NButton>
            </div>
          </div>
        </section>

        <section v-if="isWorking && sessionProgressPercent !== null" class="cs-card">
          <div class="cs-progress-row">
            <span>{{ sessionLabel || '处理中' }}</span>
            <span class="cs-muted">{{ sessionProgressPercent }}%</span>
          </div>
          <div class="cs-progress-track">
            <div class="cs-progress-fill" :style="{ width: sessionProgressPercent + '%' }" />
          </div>
        </section>

        <section class="cs-card">
          <button class="cs-collapse" type="button" @click="showUpload = !showUpload">
            <ChevronDown v-if="showUpload" :size="15" aria-hidden="true" />
            <ChevronRight v-else :size="15" aria-hidden="true" />
            <span>上传离线包</span>
            <Upload :size="15" class="cs-collapse-icon" aria-hidden="true" />
          </button>

          <div v-if="showUpload" class="cs-download">
            <div class="cs-download-head">
              <span>离线包下载地址（Linux {{ targetArch }}）</span>
              <div class="cs-download-actions">
                <a :href="downloadUrl" target="_blank" rel="noopener noreferrer">下载</a>
                <NButton text size="tiny" @click="copyDownloadUrl">复制</NButton>
              </div>
            </div>
            <code class="cs-download-url">{{ downloadUrl }}</code>
            <p class="cs-download-tip">
              版本 v{{ downloadVersion }}
              <a :href="codeServerReleasesUrl" target="_blank" rel="noopener noreferrer">
                查看所有版本
              </a>
            </p>
          </div>

          <div v-if="showUpload" class="cs-upload">
            <input
              ref="fileInput"
              type="file"
              accept=".tar.gz,.tgz,application/gzip"
              class="hidden"
              @change="handleFileChange"
            />
            <div class="cs-row">
              <NButton size="small" :disabled="uploading" @click="pickFile">
                <template #icon><Upload :size="14" /></template>
                选择文件
              </NButton>
              <span class="cs-muted cs-file-name">{{ pendingFile?.name || '未选择文件' }}</span>
            </div>
            <div class="cs-row">
              <NInput
                v-model:value="uploadVersion"
                class="cs-grow"
                placeholder="版本号，例如 4.143.1"
                :disabled="uploading"
              />
              <NSelect
                v-model:value="uploadArch"
                class="cs-arch"
                :options="archOptions"
                :disabled="uploading"
              />
              <NButton
                type="primary"
                size="small"
                :loading="uploading"
                :disabled="!pendingFile || !uploadVersion.trim()"
                @click="submitUpload"
              >
                上传
              </NButton>
            </div>
            <div v-if="uploading || uploadTotal > 0" class="cs-upload-progress">
              <div class="cs-progress-track">
                <div class="cs-progress-fill" :style="{ width: uploadPercent + '%' }" />
              </div>
              <span class="cs-muted">
                {{ formatBytes(uploadLoaded) }} / {{ formatBytes(uploadTotal) }}（{{
                  uploadPercent
                }}%）
              </span>
            </div>
            <p class="cs-tip">
              文件名需包含版本与架构，例如 hostdeck-code-server-4.143.1-linux-amd64.tar.gz。
            </p>
          </div>
        </section>
      </div>
    </div>

    <NDrawer
      v-model:show="packagesVisible"
      placement="right"
      width="min(520px, calc(100vw - 24px))"
    >
      <NDrawerContent title="code-server 离线包" closable>
        <div class="cs-drawer">
          <div class="cs-row">
            <NButton size="small" :loading="packagesLoading" @click="scanPackages">
              <template #icon><RefreshCw :size="14" /></template>
              扫描离线目录
            </NButton>
            <NButton size="small" type="primary" @click="openUploadPanel"> 上传新包 </NButton>
          </div>

          <NEmpty v-if="!packages.length && !packagesLoading" description="还没有可用的离线包" />
          <ul v-else class="cs-package-list">
            <li v-for="pkg in packages" :key="pkg.id" class="cs-package">
              <div class="cs-package-main">
                <strong>v{{ pkg.version }}</strong>
                <NTag size="small" :bordered="false">{{ pkg.arch }}</NTag>
                <span class="cs-muted">{{ formatBytes(pkg.size) }}</span>
              </div>
              <div class="cs-package-meta">
                <span class="cs-muted">上传于 {{ formatTimestamp(pkg.createdAt) }}</span>
                <NPopconfirm @positive-click="deletePackage(pkg)">
                  <template #trigger>
                    <NButton size="tiny" quaternary type="error" :loading="deletingId === pkg.id">
                      <template #icon><Trash2 :size="13" /></template>
                      删除
                    </NButton>
                  </template>
                  删除离线包 v{{ pkg.version }}（{{ pkg.arch }}）？
                </NPopconfirm>
              </div>
            </li>
          </ul>
        </div>
      </NDrawerContent>
    </NDrawer>
  </div>
</template>

<style scoped>
.code-server-view {
  --cs-border: rgba(148, 163, 184, 0.22);
  --cs-surface: rgba(255, 255, 255, 0.72);
  --cs-frame-bg: #ffffff;
  --cs-loading-bg: #f8fafc;
  --cs-surface-soft: rgba(148, 163, 184, 0.08);
  --cs-text: #1e293b;
  --cs-muted: #64748b;
  --cs-primary: #2563eb;
  --cs-danger: #dc2626;
  position: relative;
  display: flex;
  height: 100%;
  min-height: 0;
  flex-direction: column;
  color: var(--cs-text);
}

.code-server-dark {
  --cs-border: rgba(148, 163, 184, 0.16);
  --cs-surface: rgba(30, 32, 42, 0.78);
  --cs-frame-bg: #1e202a;
  --cs-loading-bg: #1e202a;
  --cs-surface-soft: rgba(148, 163, 184, 0.1);
  --cs-text: #e2e8f0;
  --cs-muted: #94a3b8;
  --cs-primary: #60a5fa;
  --cs-danger: #f87171;
}

.cs-toolbar {
  display: flex;
  flex: none;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin: 16px 16px 0;
  padding: 14px 16px;
  border: 1px solid var(--cs-border);
  border-radius: 12px;
  background: var(--cs-surface);
}

.cs-target {
  display: flex;
  flex: 1;
  min-width: 0;
  align-items: center;
  gap: 8px;
}

.cs-target svg {
  flex: none;
  color: var(--cs-primary);
}

.cs-target-text {
  overflow: hidden;
  font-size: 13px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.cs-folder {
  display: flex;
  min-width: 0;
  max-width: 360px;
  align-items: center;
  gap: 5px;
  overflow: hidden;
  padding-left: 8px;
  border-left: 1px solid var(--cs-border);
  color: var(--cs-muted);
  font-size: 12px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.cs-folder svg {
  flex: none;
  color: var(--cs-muted);
}

.cs-folder-text {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

@media (max-width: 900px) {
  .cs-folder {
    display: none;
  }
}

.cs-actions {
  display: flex;
  flex: none;
  align-items: center;
  gap: 4px;
}

.cs-zoom {
  display: flex;
  align-items: center;
  gap: 2px;
  margin-right: 4px;
  padding-right: 8px;
  border-right: 1px solid var(--cs-border);
}

.cs-zoom-value {
  min-width: 44px;
  padding: 2px 4px;
  border: 0;
  border-radius: 6px;
  background: transparent;
  color: var(--cs-muted);
  cursor: pointer;
  font-size: 12px;
  font-variant-numeric: tabular-nums;
}

.cs-zoom-value:hover {
  background: var(--cs-surface-soft);
  color: var(--cs-text);
}

.cs-body {
  display: flex;
  min-height: 0;
  flex: 1;
  flex-direction: column;
}

.cs-center {
  display: grid;
  min-height: 0;
  flex: 1;
  place-items: center;
  padding: 24px;
}

.cs-running {
  display: flex;
  min-height: 0;
  flex: 1;
  flex-direction: column;
}

.cs-stopping {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  color: var(--cs-muted);
  font-size: 13px;
}

.cs-toolbar + .cs-body .cs-running {
  margin-top: 12px;
}

.cs-frame-wrap {
  position: relative;
  min-height: 0;
  flex: 1;
  overflow: hidden;
  background: var(--cs-frame-bg);
}

.cs-frame {
  width: 100%;
  height: 100%;
  border: 0;
  opacity: 0;
  transition: opacity 0.2s ease;
}

.cs-frame-ready {
  opacity: 1;
}

.cs-frame-loading {
  position: absolute;
  inset: 0;
  z-index: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: var(--cs-muted);
  font-size: 13px;
  background: var(--cs-loading-bg);
}

.cs-setup {
  display: flex;
  min-height: 0;
  flex: 1;
  flex-direction: column;
  gap: 12px;
  padding: 16px;
  overflow: auto;
}

.cs-card {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 14px 16px;
  border: 1px solid var(--cs-border);
  border-radius: 12px;
  background: var(--cs-surface);
}

.cs-card-header {
  display: flex;
  align-items: center;
  gap: 8px;
}

.cs-card-header svg {
  color: var(--cs-primary);
}

.cs-card-header h2 {
  margin: 0;
  font-size: 14px;
  font-weight: 650;
}

.cs-muted {
  color: var(--cs-muted);
  font-size: 12px;
}

.cs-issue-list {
  margin: 0;
  padding-left: 18px;
  font-size: 13px;
}

.cs-facts {
  display: grid;
  margin: 0;
  gap: 8px 18px;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
}

.cs-facts div {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  padding: 6px 10px;
  border-radius: 8px;
  background: var(--cs-surface-soft);
}

.cs-facts dt {
  color: var(--cs-muted);
  font-size: 12px;
}

.cs-facts dd {
  margin: 0;
  font-size: 13px;
  font-weight: 600;
}

.cs-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.cs-row-between {
  flex-wrap: wrap;
  justify-content: space-between;
}

.cs-grow {
  min-width: 0;
  flex: 1;
}

.cs-arch {
  width: 190px;
}

.cs-installed {
  font-size: 13px;
  font-weight: 600;
}

.cs-empty-row {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--cs-muted);
  font-size: 13px;
}

.cs-empty-row svg {
  flex: none;
  color: #d97706;
}

.cs-progress-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 13px;
}

.cs-progress-track {
  width: 100%;
  height: 6px;
  overflow: hidden;
  border-radius: 999px;
  background: var(--cs-surface-soft);
}

.cs-progress-fill {
  height: 100%;
  border-radius: 999px;
  background: var(--cs-primary);
  transition: width 0.2s ease;
}

.cs-collapse {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 6px;
  padding: 0;
  color: inherit;
  font-size: 13px;
  font-weight: 650;
  text-align: left;
  border: 0;
  background: transparent;
  cursor: pointer;
}

.cs-collapse-icon {
  margin-left: auto;
  color: var(--cs-muted);
}

.cs-upload {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding-top: 4px;
}

.cs-file-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.cs-upload-progress {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.cs-tip {
  margin: 0;
  color: var(--cs-muted);
  font-size: 12px;
}

.cs-download {
  display: flex;
  flex-direction: column;
  gap: 7px;
  padding: 10px;
  border: 1px solid var(--cs-border);
  border-radius: 10px;
  background: var(--cs-surface-soft);
}

.cs-download-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  color: var(--cs-muted);
  font-size: 12px;
}

.cs-download-actions {
  display: flex;
  align-items: center;
  gap: 10px;
}

.cs-download-actions a,
.cs-download-tip a {
  color: var(--cs-primary);
  font-size: 12px;
  text-decoration: none;
}

.cs-download-actions a:hover,
.cs-download-tip a:hover {
  text-decoration: underline;
}

.cs-download-url {
  display: block;
  overflow-wrap: anywhere;
  color: var(--cs-text);
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 11px;
  line-height: 1.6;
  user-select: all;
}

.cs-download-tip {
  margin: 0;
  color: var(--cs-muted);
  font-size: 11px;
  line-height: 1.6;
}

.cs-drawer {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.cs-package-list {
  display: flex;
  margin: 0;
  padding: 0;
  flex-direction: column;
  gap: 10px;
  list-style: none;
}

.cs-package {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 12px 14px;
  border: 1px solid var(--cs-border);
  border-radius: 10px;
}

.cs-package-main,
.cs-package-meta {
  display: flex;
  align-items: center;
  gap: 8px;
}

.cs-package-main strong {
  font-size: 14px;
}

.cs-package-meta {
  justify-content: space-between;
}

@media (max-width: 640px) {
  .cs-toolbar {
    margin: 10px 10px 0;
  }

  .cs-setup {
    padding: 10px;
  }

  .cs-arch {
    width: 140px;
  }
}
</style>

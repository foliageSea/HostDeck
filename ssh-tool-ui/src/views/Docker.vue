<script setup lang="ts">
import type { DockerContainer, DockerImage } from '@/api/docker';
import { useDockerPageState } from '@/composables/useDockerPageState';
import ContainerPanel from '@/components/docker/ContainerPanel.vue';
import ImagePanel from '@/components/docker/ImagePanel.vue';
import {
  FileText,
  Container,
  HardDrive,
  RefreshCw,
  AlertCircle,
  Copy,
  Download,
  Info,
  Plus,
  Trash2,
} from 'lucide-vue-next';
import { Button } from '@/components/ui/button';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { Skeleton } from '@/components/ui/skeleton';

const {
  activeTab,
  containers,
  images,
  loading,
  dockerAvailable,
  refreshing,
  batchProcessing,
  containerNameQuery,
  containerImageQuery,
  containerStateFilter,
  containerSortBy,
  containerSortOrder,
  selectedContainerIds,
  imageQuery,
  imageUsageFilter,
  imageSortBy,
  imageSortOrder,
  logsDialogOpen,
  logsContainer,
  logsLoading,
  logsRefreshing,
  logsTail,
  logsKeyword,
  logsAutoRefresh,
  showLogTimestamps,
  logsLastUpdatedAt,
  confirmDialogOpen,
  confirmAction,
  confirmItem,
  confirmForce,
  detailDialogOpen,
  detailContainer,
  detailLoading,
  detailInspect,
  rawInspectDialogOpen,
  createDialogOpen,
  creatingContainer,
  recreateLoadingId,
  renameDialogOpen,
  renamingContainer,
  renamingContainerName,
  imagePullDialogOpen,
  imagePullInput,
  imagePulling,
  imageTagDialogOpen,
  imageTagSource,
  imageTagTarget,
  imageTagging,
  imageHistoryDialogOpen,
  imageHistoryLoading,
  imageHistoryTitle,
  imageHistoryItems,
  imageRefsDialogOpen,
  imageRefsLoading,
  imageRefsTitle,
  imageRefsItems,
  createContainerForm,
  createContainerPorts,
  createContainerEnvs,
  createContainerVolumes,
  createContainerCmdText,
  createContainerEntrypointText,
  isConnected,
  logTailOptions,
  runningContainers,
  exitedContainers,
  pausedContainers,
  selectedContainerSet,
  selectedRunningContainers,
  selectedStoppedContainers,
  filteredContainers,
  allVisibleContainersSelected,
  detailPorts,
  detailNetworks,
  detailStats,
  filteredImages,
  displayedLogs,
  confirmTitle,
  confirmButtonText,
  refresh,
  getContainerStats,
  isFrequentRestart,
  isUnhealthyContainer,
  isExitedAbnormally,
  openContainerDetail,
  startContainer,
  stopContainer,
  restartContainer,
  pauseContainer,
  unpauseContainer,
  openRenameDialog,
  submitRenameContainer,
  recreateContainer,
  openCreateContainerDialog,
  submitCreateContainer,
  addCreatePort,
  removeCreatePort,
  addCreateEnv,
  removeCreateEnv,
  addCreateVolume,
  removeCreateVolume,
  openImagePullDialog,
  submitPullImage,
  openImageTagDialog,
  submitTagImage,
  viewImageHistory,
  viewImageRefs,
  openRawInspect,
  rawInspectText,
  downloadInspectConfig,
  toggleContainerSelection,
  toggleSelectAllVisibleContainers,
  clearSelectedContainers,
  batchStartSelected,
  batchStopSelected,
  showRemoveContainerConfirm,
  showRemoveImageConfirm,
  showRemoveStoppedContainersConfirm,
  showPruneDanglingConfirm,
  showPruneUnusedConfirm,
  confirmRemove,
  refreshLogs,
  viewLogs,
  copyLogs,
  downloadLogs,
  enterShell,
  formatDate,
  shortId,
  copyToClipboard,
  getPortDisplay,
} = useDockerPageState();

const setContainerNameQuery = (value: string) => {
  containerNameQuery.value = value;
};

const setContainerImageQuery = (value: string) => {
  containerImageQuery.value = value;
};

const setContainerStateFilter = (value: 'all' | 'running' | 'exited' | 'paused') => {
  containerStateFilter.value = value;
};

const setContainerSortBy = (value: 'createdAt' | 'name' | 'image') => {
  containerSortBy.value = value;
};

const setContainerSortOrder = (value: 'asc' | 'desc') => {
  containerSortOrder.value = value;
};

const setImageQuery = (value: string) => {
  imageQuery.value = value;
};

const setImageUsageFilter = (value: 'all' | 'dangling' | 'unused') => {
  imageUsageFilter.value = value;
};

const setImageSortBy = (value: 'createdAt' | 'repository' | 'tag' | 'size') => {
  imageSortBy.value = value;
};

const setImageSortOrder = (value: 'asc' | 'desc') => {
  imageSortOrder.value = value;
};
</script>

<template>
  <div class="h-full flex flex-col bg-background">
    <div class="flex items-center justify-between px-4 py-3 border-b">
      <div class="flex items-center gap-4">
        <h2 class="text-lg font-semibold">Docker 管理</h2>
        <div class="flex bg-muted rounded-lg p-1">
          <button class="px-3 py-1 text-sm rounded-md transition-colors"
            :class="activeTab === 'containers' ? 'bg-background shadow-sm' : 'text-muted-foreground hover:text-foreground'"
            @click="activeTab = 'containers'">
            <div class="flex items-center gap-2">
              <Container class="w-4 h-4" />
              容器
              <span v-if="containers.length > 0"
                class="inline-flex items-center rounded-md bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-800">
                {{ containers.length }}
              </span>
            </div>
          </button>
          <button class="px-3 py-1 text-sm rounded-md transition-colors"
            :class="activeTab === 'images' ? 'bg-background shadow-sm' : 'text-muted-foreground hover:text-foreground'"
            @click="activeTab = 'images'">
            <div class="flex items-center gap-2">
              <HardDrive class="w-4 h-4" />
              镜像
              <span v-if="images.length > 0"
                class="inline-flex items-center rounded-md bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-800">
                {{ images.length }}
              </span>
            </div>
          </button>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <Button
          v-if="activeTab === 'containers'"
          variant="outline"
          size="sm"
          :disabled="!dockerAvailable"
          @click="openCreateContainerDialog"
        >
          <Plus class="w-4 h-4 mr-2"/>
          新建容器
        </Button>
        <Button
          v-if="activeTab === 'images'"
          variant="outline"
          size="sm"
          :disabled="!dockerAvailable"
          @click="openImagePullDialog"
        >
          <Download class="w-4 h-4 mr-2"/>
          拉取镜像
        </Button>
        <Button variant="outline" size="sm" :disabled="refreshing || !dockerAvailable" @click="refresh">
          <RefreshCw class="w-4 h-4 mr-2" :class="{ 'animate-spin': refreshing }"/>
          刷新
        </Button>
      </div>
    </div>

    <div class="flex-1 overflow-auto custom-scrollbar p-4">
      <div v-if="!isConnected" class="h-full flex flex-col items-center justify-center text-muted-foreground">
        <AlertCircle class="w-12 h-12 mb-4 opacity-50"/>
        <p>请先连接 SSH 服务器</p>
      </div>

      <div v-else-if="dockerAvailable === false" class="h-full flex flex-col items-center justify-center text-muted-foreground">
        <AlertCircle class="w-12 h-12 mb-4 opacity-50"/>
        <p>该服务器未安装 Docker 或无法访问</p>
      </div>

      <div v-else-if="loading" class="space-y-4">
        <Skeleton v-for="i in 5" :key="i" class="h-12 w-full"/>
      </div>

      <ContainerPanel
        v-else-if="activeTab === 'containers'"
        :containers="containers"
        :running-containers="runningContainers"
        :exited-containers="exitedContainers"
        :paused-containers="pausedContainers"
        :container-name-query="containerNameQuery"
        :container-image-query="containerImageQuery"
        :container-state-filter="containerStateFilter"
        :container-sort-by="containerSortBy"
        :container-sort-order="containerSortOrder"
        :set-container-name-query="setContainerNameQuery"
        :set-container-image-query="setContainerImageQuery"
        :set-container-state-filter="setContainerStateFilter"
        :set-container-sort-by="setContainerSortBy"
        :set-container-sort-order="setContainerSortOrder"
        :selected-container-ids="selectedContainerIds"
        :selected-stopped-containers="selectedStoppedContainers"
        :selected-running-containers="selectedRunningContainers"
        :batch-processing="batchProcessing"
        :all-visible-containers-selected="allVisibleContainersSelected"
        :filtered-containers="filteredContainers"
        :selected-container-set="selectedContainerSet"
        :recreate-loading-id="recreateLoadingId"
        :get-port-display="getPortDisplay"
        :get-container-stats="getContainerStats"
        :format-date="formatDate"
        :short-id="shortId"
        :is-unhealthy-container="isUnhealthyContainer"
        :is-frequent-restart="isFrequentRestart"
        :is-exited-abnormally="isExitedAbnormally"
        :copy-to-clipboard="copyToClipboard"
        :clear-selected-containers="clearSelectedContainers"
        :batch-start-selected="batchStartSelected"
        :batch-stop-selected="batchStopSelected"
        :show-remove-stopped-containers-confirm="showRemoveStoppedContainersConfirm"
        :toggle-select-all-visible-containers="toggleSelectAllVisibleContainers"
        :toggle-container-selection="toggleContainerSelection"
        :open-container-detail="openContainerDetail"
        :start-container="startContainer"
        :stop-container="stopContainer"
        :restart-container="restartContainer"
        :pause-container="pauseContainer"
        :unpause-container="unpauseContainer"
        :view-logs="viewLogs"
        :open-rename-dialog="openRenameDialog"
        :recreate-container="recreateContainer"
        :enter-shell="enterShell"
        :show-remove-container-confirm="showRemoveContainerConfirm"
      />

      <ImagePanel
        v-else-if="activeTab === 'images'"
        :image-query="imageQuery"
        :image-usage-filter="imageUsageFilter"
        :image-sort-by="imageSortBy"
        :image-sort-order="imageSortOrder"
        :set-image-query="setImageQuery"
        :set-image-usage-filter="setImageUsageFilter"
        :set-image-sort-by="setImageSortBy"
        :set-image-sort-order="setImageSortOrder"
        :filtered-images="filteredImages"
        :short-id="shortId"
        :format-date="formatDate"
        :show-prune-dangling-confirm="showPruneDanglingConfirm"
        :show-prune-unused-confirm="showPruneUnusedConfirm"
        :view-image-history="viewImageHistory"
        :view-image-refs="viewImageRefs"
        :open-image-tag-dialog="openImageTagDialog"
        :show-remove-image-confirm="showRemoveImageConfirm"
      />
    </div>

    <Dialog v-model:open="logsDialogOpen">
      <DialogContent class="max-w-4xl max-h-[80vh] flex flex-col">
        <DialogHeader>
          <DialogTitle class="flex items-center gap-2">
            <FileText class="w-5 h-5"/>
            容器日志: {{ logsContainer?.name }}
          </DialogTitle>
          <DialogDescription>
            显示最近 {{ logsTail }} 行日志
          </DialogDescription>
        </DialogHeader>

        <div class="border rounded-md p-3 space-y-3 bg-muted/20">
          <div class="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-6 gap-2">
            <select v-model="logsTail"
              class="h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring">
              <option v-for="option in logTailOptions" :key="option" :value="option">{{ option }} 行</option>
            </select>

            <Input v-model="logsKeyword" class="md:col-span-2" placeholder="关键字筛选"/>

            <label class="h-9 px-3 border rounded-md bg-background inline-flex items-center gap-2 text-sm">
              <input v-model="logsAutoRefresh" type="checkbox">
              自动刷新
            </label>
            <label class="h-9 px-3 border rounded-md bg-background inline-flex items-center gap-2 text-sm">
              <input v-model="showLogTimestamps" type="checkbox">
              显示时间戳
            </label>

            <Button size="sm" variant="outline" :disabled="logsLoading || logsRefreshing" @click="refreshLogs(true)">
              <RefreshCw class="w-4 h-4" :class="{ 'animate-spin': logsRefreshing }"/>
              刷新日志
            </Button>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <Button size="sm" variant="outline" @click="copyLogs">
              <Copy class="w-4 h-4"/>
              复制
            </Button>
            <Button size="sm" variant="outline" @click="downloadLogs">
              <Download class="w-4 h-4"/>
              下载
            </Button>
            <span class="text-xs text-muted-foreground ml-auto" v-if="logsLastUpdatedAt">
              最近更新：{{ logsLastUpdatedAt.toLocaleTimeString('zh-CN') }}
            </span>
          </div>
        </div>

        <div class="flex-1 bg-black rounded-md p-4 min-h-[400px] overflow-auto custom-scrollbar">
          <div v-if="logsLoading" class="space-y-2">
            <Skeleton v-for="i in 10" :key="i" class="h-4 w-full"/>
          </div>
          <pre v-else class="text-sm text-gray-300 font-mono whitespace-pre-wrap break-all">{{ displayedLogs || '暂无日志' }}</pre>
        </div>
      </DialogContent>
    </Dialog>

    <Dialog v-model:open="detailDialogOpen">
      <DialogContent class="max-w-5xl max-h-[85vh] flex flex-col">
        <DialogHeader>
          <DialogTitle class="flex items-center gap-2">
            <Info class="w-5 h-5"/>
            容器详情: {{ detailContainer?.name }}
          </DialogTitle>
          <DialogDescription>
            容器诊断信息与 inspect 数据
          </DialogDescription>
        </DialogHeader>

        <div class="flex-1 overflow-auto custom-scrollbar space-y-3 pr-1">
          <div v-if="detailLoading" class="space-y-2">
            <Skeleton v-for="i in 8" :key="i" class="h-6 w-full"/>
          </div>

          <div v-else-if="detailInspect" class="space-y-3">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div class="border rounded-md p-3 space-y-2">
                <div class="text-xs text-muted-foreground">容器 ID</div>
                <code class="text-xs break-all">{{ detailInspect.Id || detailContainer?.id || '-' }}</code>
              </div>
              <div class="border rounded-md p-3 space-y-2">
                <div class="text-xs text-muted-foreground">镜像</div>
                <div class="text-sm break-all">{{ detailInspect.Config?.Image || detailContainer?.image || '-' }}</div>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div class="border rounded-md p-3 space-y-2">
                <div class="text-xs text-muted-foreground">状态</div>
                <div class="flex flex-wrap gap-2 text-sm">
                  <span class="inline-flex rounded-full px-2 py-0.5 bg-muted">{{ detailInspect.State?.Status || '-' }}</span>
                  <span class="inline-flex rounded-full px-2 py-0.5 bg-muted">重启: {{ detailInspect.State?.RestartCount ?? 0 }}</span>
                  <span class="inline-flex rounded-full px-2 py-0.5 bg-muted">退出码: {{ detailInspect.State?.ExitCode ?? 0 }}</span>
                  <span class="inline-flex rounded-full px-2 py-0.5 bg-muted">健康: {{ detailInspect.State?.Health?.Status || '-' }}</span>
                </div>
              </div>
              <div class="border rounded-md p-3 space-y-2">
                <div class="text-xs text-muted-foreground">Restart Policy</div>
                <div class="text-sm">{{ detailInspect.HostConfig?.RestartPolicy?.Name || '-' }}</div>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div class="border rounded-md p-3 space-y-2">
                <div class="text-xs text-muted-foreground">资源监控</div>
                <div class="text-sm space-y-1">
                  <div>CPU: {{ detailStats?.cpuPercent || '-' }}</div>
                  <div>内存: {{ detailStats?.memPercent || '-' }} ({{ detailStats?.memUsage || '-' }})</div>
                  <div>网络 IO: {{ detailStats?.netIO || '-' }}</div>
                  <div>磁盘 IO: {{ detailStats?.blockIO || '-' }}</div>
                  <div>PIDs: {{ detailStats?.pids || '-' }}</div>
                </div>
              </div>
              <div class="border rounded-md p-3 space-y-2">
                <div class="text-xs text-muted-foreground">启动命令</div>
                <code class="text-xs break-all">{{ (detailInspect.Config?.Cmd || []).join(' ') || '-' }}</code>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div class="border rounded-md p-3 space-y-2">
                <div class="text-xs text-muted-foreground">端口映射</div>
                <div v-if="detailPorts.length" class="space-y-1 text-xs">
                  <div v-for="port in detailPorts" :key="port">{{ port }}</div>
                </div>
                <div v-else class="text-sm text-muted-foreground">-</div>
              </div>
              <div class="border rounded-md p-3 space-y-2">
                <div class="text-xs text-muted-foreground">网络信息</div>
                <div v-if="detailNetworks.length" class="space-y-1 text-xs">
                  <div v-for="network in detailNetworks" :key="network.name">
                    {{ network.name }} ({{ network.ip }})
                  </div>
                </div>
                <div v-else class="text-sm text-muted-foreground">-</div>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div class="border rounded-md p-3 space-y-2">
                <div class="text-xs text-muted-foreground">挂载卷</div>
                <div v-if="detailInspect.Mounts?.length" class="space-y-1 text-xs">
                  <div v-for="mount in detailInspect.Mounts" :key="`${mount.Source}-${mount.Destination}`">
                    {{ mount.Source || '-' }} -> {{ mount.Destination || '-' }}
                  </div>
                </div>
                <div v-else class="text-sm text-muted-foreground">-</div>
              </div>
              <div class="border rounded-md p-3 space-y-2">
                <div class="text-xs text-muted-foreground">环境变量</div>
                <div v-if="detailInspect.Config?.Env?.length" class="max-h-40 overflow-auto custom-scrollbar text-xs space-y-1">
                  <div v-for="env in detailInspect.Config?.Env" :key="env">{{ env }}</div>
                </div>
                <div v-else class="text-sm text-muted-foreground">-</div>
              </div>
            </div>

            <div class="border rounded-md p-3 space-y-2">
              <div class="text-xs text-muted-foreground">Labels</div>
              <div v-if="detailInspect.Config?.Labels && Object.keys(detailInspect.Config.Labels).length" class="text-xs space-y-1">
                <div v-for="(value, key) in detailInspect.Config.Labels" :key="key">
                  {{ key }}={{ value }}
                </div>
              </div>
              <div v-else class="text-sm text-muted-foreground">-</div>
            </div>

            <div class="flex flex-wrap justify-end gap-2">
              <Button size="sm" variant="outline" @click="openRawInspect">
                <Info class="w-4 h-4"/>
                查看原始 inspect JSON
              </Button>
              <Button size="sm" variant="outline" @click="downloadInspectConfig">
                <Download class="w-4 h-4"/>
                导出容器配置
              </Button>
              <Button size="sm" variant="outline" @click="detailContainer && viewLogs(detailContainer)">
                <FileText class="w-4 h-4"/>
                快速查看最近日志
              </Button>
            </div>
          </div>

          <div v-else class="text-sm text-muted-foreground">暂无详情数据</div>
        </div>
      </DialogContent>
    </Dialog>

    <Dialog v-model:open="rawInspectDialogOpen">
      <DialogContent class="max-w-5xl max-h-[85vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>原始 inspect JSON</DialogTitle>
          <DialogDescription>
            可复制或用于排障比对
          </DialogDescription>
        </DialogHeader>
        <div class="flex-1 overflow-auto bg-black rounded-md p-3">
          <pre class="text-xs text-gray-300 font-mono whitespace-pre-wrap break-all">{{ rawInspectText || '{}' }}</pre>
        </div>
      </DialogContent>
    </Dialog>

    <Dialog v-model:open="renameDialogOpen">
      <DialogContent class="max-w-md">
        <DialogHeader>
          <DialogTitle>重命名容器</DialogTitle>
          <DialogDescription>
            输入新的容器名称
          </DialogDescription>
        </DialogHeader>
        <div class="space-y-3">
          <Input v-model="renamingContainerName" placeholder="例如: nginx-prod"/>
        </div>
        <div class="flex justify-end gap-2 mt-4">
          <Button variant="outline" @click="renameDialogOpen = false">取消</Button>
          <Button :disabled="renamingContainer" @click="submitRenameContainer">
            {{ renamingContainer ? '提交中...' : '确认' }}
          </Button>
        </div>
      </DialogContent>
    </Dialog>

    <Dialog v-model:open="createDialogOpen">
      <DialogContent class="max-w-3xl max-h-[85vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>新建容器</DialogTitle>
          <DialogDescription>
            请选择镜像并配置容器参数
          </DialogDescription>
        </DialogHeader>
        <div class="flex-1 overflow-auto custom-scrollbar pr-1 space-y-3">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">镜像</div>
              <select
                v-model="createContainerForm.image"
                class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm text-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              >
                <option value="" disabled>请选择镜像</option>
                <option
                  v-for="image in images"
                  :key="`${image.id}-${image.repository}-${image.tag}`"
                  :value="`${image.repository}:${image.tag}`"
                >
                  {{ image.repository }}:{{ image.tag }}
                </option>
              </select>
              <p v-if="images.length === 0" class="text-xs text-muted-foreground">
                暂无可选镜像，请先在镜像页拉取镜像
              </p>
            </div>
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">容器名称（可选）</div>
              <Input v-model="createContainerForm.name" placeholder="my-nginx"/>
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">端口映射（如 8080:80）</div>
              <div class="space-y-2">
                <div v-for="(_, index) in createContainerPorts" :key="`port-${index}`" class="flex gap-2">
                  <Input v-model="createContainerPorts[index]" placeholder="8080:80"/>
                  <Button
                    variant="outline"
                    size="icon"
                    :disabled="createContainerPorts.length === 1"
                    @click="removeCreatePort(index)"
                  >
                    <Trash2 class="w-4 h-4"/>
                  </Button>
                </div>
                <Button variant="outline" size="sm" @click="addCreatePort">添加端口映射</Button>
              </div>
            </div>
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">环境变量（如 KEY=VALUE）</div>
              <div class="space-y-2">
                <div v-for="(_, index) in createContainerEnvs" :key="`env-${index}`" class="flex gap-2">
                  <Input v-model="createContainerEnvs[index]" placeholder="KEY=VALUE"/>
                  <Button
                    variant="outline"
                    size="icon"
                    :disabled="createContainerEnvs.length === 1"
                    @click="removeCreateEnv(index)"
                  >
                    <Trash2 class="w-4 h-4"/>
                  </Button>
                </div>
                <Button variant="outline" size="sm" @click="addCreateEnv">添加环境变量</Button>
              </div>
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">卷挂载（如 /data:/app/data）</div>
              <div class="space-y-2">
                <div v-for="(_, index) in createContainerVolumes" :key="`volume-${index}`" class="flex gap-2">
                  <Input v-model="createContainerVolumes[index]" placeholder="/data:/app/data"/>
                  <Button
                    variant="outline"
                    size="icon"
                    :disabled="createContainerVolumes.length === 1"
                    @click="removeCreateVolume(index)"
                  >
                    <Trash2 class="w-4 h-4"/>
                  </Button>
                </div>
                <Button variant="outline" size="sm" @click="addCreateVolume">添加卷挂载</Button>
              </div>
            </div>
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">Restart Policy</div>
              <select
                v-model="createContainerForm.restartPolicy"
                class="h-9 w-full rounded-md border border-input bg-background px-3 text-sm text-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              >
                <option value="no">no</option>
                <option value="always">always</option>
                <option value="unless-stopped">unless-stopped</option>
                <option value="on-failure">on-failure</option>
              </select>
              <label class="inline-flex items-center gap-2 text-sm mt-2 text-foreground">
                <input
                  v-model="createContainerForm.start"
                  type="checkbox"
                  class="h-4 w-4 rounded border-input bg-background text-primary accent-primary"
                >
                创建后自动启动
              </label>
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">Entrypoint（每行一个参数）</div>
              <textarea
                v-model="createContainerEntrypointText"
                class="w-full min-h-20 rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              ></textarea>
            </div>
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">命令 CMD（每行一个参数）</div>
              <textarea
                v-model="createContainerCmdText"
                class="w-full min-h-20 rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              ></textarea>
            </div>
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-4">
          <Button variant="outline" @click="createDialogOpen = false">取消</Button>
          <Button :disabled="creatingContainer" @click="submitCreateContainer">
            {{ creatingContainer ? '创建中...' : '创建容器' }}
          </Button>
        </div>
      </DialogContent>
    </Dialog>

    <Dialog v-model:open="imagePullDialogOpen">
      <DialogContent class="max-w-md">
        <DialogHeader>
          <DialogTitle>拉取镜像</DialogTitle>
          <DialogDescription>
            输入镜像名称，例如 redis:7
          </DialogDescription>
        </DialogHeader>
        <Input v-model="imagePullInput" placeholder="repository:tag"/>
        <div class="flex justify-end gap-2 mt-4">
          <Button variant="outline" @click="imagePullDialogOpen = false">取消</Button>
          <Button :disabled="imagePulling" @click="submitPullImage">
            {{ imagePulling ? '拉取中...' : '开始拉取' }}
          </Button>
        </div>
      </DialogContent>
    </Dialog>

    <Dialog v-model:open="imageTagDialogOpen">
      <DialogContent class="max-w-lg">
        <DialogHeader>
          <DialogTitle>镜像重新打标签</DialogTitle>
          <DialogDescription>
            将源镜像标记为新标签
          </DialogDescription>
        </DialogHeader>
        <div class="space-y-3">
          <div>
            <div class="text-sm text-muted-foreground mb-1">源镜像</div>
            <Input v-model="imageTagSource" placeholder="old-repo:old-tag"/>
          </div>
          <div>
            <div class="text-sm text-muted-foreground mb-1">目标镜像</div>
            <Input v-model="imageTagTarget" placeholder="new-repo:new-tag"/>
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-4">
          <Button variant="outline" @click="imageTagDialogOpen = false">取消</Button>
          <Button :disabled="imageTagging" @click="submitTagImage">
            {{ imageTagging ? '提交中...' : '确认打标签' }}
          </Button>
        </div>
      </DialogContent>
    </Dialog>

    <Dialog v-model:open="imageHistoryDialogOpen">
      <DialogContent class="max-w-4xl max-h-[85vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>镜像历史</DialogTitle>
          <DialogDescription>
            {{ imageHistoryTitle }}
          </DialogDescription>
        </DialogHeader>
        <div class="flex-1 overflow-auto custom-scrollbar border rounded-md">
          <Table>
            <TableHeader>
              <TableRow class="bg-muted/50">
                <TableHead>ID</TableHead>
                <TableHead>创建时间</TableHead>
                <TableHead>命令</TableHead>
                <TableHead>大小</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableRow v-if="imageHistoryLoading">
                <TableCell colspan="4" class="py-8 text-center text-muted-foreground">加载中...</TableCell>
              </TableRow>
              <TableRow v-else-if="imageHistoryItems.length === 0">
                <TableCell colspan="4" class="py-8 text-center text-muted-foreground">暂无历史数据</TableCell>
              </TableRow>
              <TableRow v-for="item in imageHistoryItems" :key="`${item.id}-${item.createdAt}-${item.size}`">
                <TableCell class="font-mono text-xs">{{ shortId(item.id) }}</TableCell>
                <TableCell class="text-xs">{{ item.createdSince || item.createdAt || '-' }}</TableCell>
                <TableCell class="text-xs break-all">{{ item.createdBy || '-' }}</TableCell>
                <TableCell class="text-xs">{{ item.size || '-' }}</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </div>
      </DialogContent>
    </Dialog>

    <Dialog v-model:open="imageRefsDialogOpen">
      <DialogContent class="max-w-3xl max-h-[80vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>镜像引用容器</DialogTitle>
          <DialogDescription>
            {{ imageRefsTitle }}
          </DialogDescription>
        </DialogHeader>
        <div class="flex-1 overflow-auto custom-scrollbar border rounded-md">
          <Table>
            <TableHeader>
              <TableRow class="bg-muted/50">
                <TableHead>ID</TableHead>
                <TableHead>名称</TableHead>
                <TableHead>状态</TableHead>
                <TableHead>详情</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableRow v-if="imageRefsLoading">
                <TableCell colspan="4" class="py-8 text-center text-muted-foreground">加载中...</TableCell>
              </TableRow>
              <TableRow v-else-if="imageRefsItems.length === 0">
                <TableCell colspan="4" class="py-8 text-center text-muted-foreground">暂无引用容器</TableCell>
              </TableRow>
              <TableRow v-for="item in imageRefsItems" :key="item.id">
                <TableCell class="font-mono text-xs">{{ shortId(item.id) }}</TableCell>
                <TableCell class="text-sm">{{ item.name }}</TableCell>
                <TableCell>
                  <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs bg-muted">{{ item.state || '-' }}</span>
                </TableCell>
                <TableCell class="text-xs text-muted-foreground">{{ item.status || '-' }}</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </div>
      </DialogContent>
    </Dialog>

    <AlertDialog v-model:open="confirmDialogOpen">
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{{ confirmTitle }}</AlertDialogTitle>
          <AlertDialogDescription>
            <span v-if="confirmAction === 'removeContainer'">
              确定要删除容器 <strong>{{ (confirmItem as DockerContainer)?.name }}</strong> 吗？
              <span v-if="confirmForce" class="block mt-2 text-red-500">
                警告：该容器正在运行，强制删除可能导致数据丢失。
              </span>
            </span>
            <span v-else-if="confirmAction === 'removeImage'">
              确定要删除镜像 <strong>{{ (confirmItem as DockerImage)?.repository }}:{{ (confirmItem as DockerImage)?.tag
              }}</strong> 吗？
            </span>
            <span v-else-if="confirmAction === 'pruneDangling'">
              确定要清理所有 dangling 镜像吗？
            </span>
            <span v-else-if="confirmAction === 'pruneUnused'">
              确定要清理所有无引用镜像吗？该操作会删除未被容器使用的镜像。
            </span>
            <span v-else-if="confirmAction === 'removeStoppedContainers'">
              确定要删除所有已停止容器吗？
            </span>
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>取消</AlertDialogCancel>
          <AlertDialogAction class="bg-red-600 hover:bg-red-700" @click="confirmRemove">
            {{ confirmButtonText }}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </div>
</template>

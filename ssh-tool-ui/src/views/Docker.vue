<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useSshStore } from '@/stores/ssh';
import { useDesktopStore } from '@/stores/desktop';
import {
  dockerApi,
  type DockerContainer,
  type DockerImage,
  type DockerImageHistoryItem,
  type DockerImageContainerRef,
  type DockerCreateContainerPayload,
  type DockerContainerInspect,
  type DockerContainerStats,
  type DockerContainerDiagnostic,
} from '@/api/docker';
import { toast } from 'vue-sonner';
import {
  Play,
  Square,
  RotateCw,
  Trash2,
  FileText,
  Terminal,
  Container,
  HardDrive,
  RefreshCw,
  AlertCircle,
  Copy,
  Download,
  Info,
  Pause,
  Tag,
  Plus,
  Pencil,
} from 'lucide-vue-next';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow
} from '@/components/ui/table';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';
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

type ConfirmAction =
  | 'removeContainer'
  | 'removeImage'
  | 'pruneDangling'
  | 'pruneUnused'
  | 'removeStoppedContainers';

const LOG_TAIL_OPTIONS = [100, 200, 500, 1000] as const;
type LogTailOption = (typeof LOG_TAIL_OPTIONS)[number];

const sshStore = useSshStore();
const desktopStore = useDesktopStore();

const activeTab = ref<'containers' | 'images'>('containers');
const containers = ref<DockerContainer[]>([]);
const images = ref<DockerImage[]>([]);
const loading = ref(false);
const dockerAvailable = ref<boolean | null>(null);
const refreshing = ref(false);
const batchProcessing = ref(false);

const containerNameQuery = ref('');
const containerImageQuery = ref('');
const containerStateFilter = ref<'all' | 'running' | 'exited' | 'paused'>('all');
const containerSortBy = ref<'createdAt' | 'name' | 'image'>('createdAt');
const containerSortOrder = ref<'asc' | 'desc'>('desc');
const selectedContainerIds = ref<string[]>([]);

const imageQuery = ref('');
const imageUsageFilter = ref<'all' | 'dangling' | 'unused'>('all');
const imageSortBy = ref<'createdAt' | 'repository' | 'tag' | 'size'>('createdAt');
const imageSortOrder = ref<'asc' | 'desc'>('desc');

const logsDialogOpen = ref(false);
const logsContainer = ref<DockerContainer | null>(null);
const logsContent = ref('');
const logsLoading = ref(false);
const logsRefreshing = ref(false);
const logsTail = ref<LogTailOption>(200);
const logsKeyword = ref('');
const logsAutoRefresh = ref(false);
const showLogTimestamps = ref(true);
const logsLastUpdatedAt = ref<Date | null>(null);

const confirmDialogOpen = ref(false);
const confirmAction = ref<ConfirmAction | null>(null);
const confirmItem = ref<DockerContainer | DockerImage | null>(null);
const confirmForce = ref(false);

const detailDialogOpen = ref(false);
const detailContainer = ref<DockerContainer | null>(null);
const detailLoading = ref(false);
const detailInspect = ref<DockerContainerInspect | null>(null);

const rawInspectDialogOpen = ref(false);
const createDialogOpen = ref(false);
const creatingContainer = ref(false);
const recreateLoadingId = ref<string | null>(null);
const renameDialogOpen = ref(false);
const renamingContainer = ref(false);
const renamingContainerId = ref('');
const renamingContainerName = ref('');

const imagePullDialogOpen = ref(false);
const imagePullInput = ref('');
const imagePulling = ref(false);
const imageTagDialogOpen = ref(false);
const imageTagSource = ref('');
const imageTagTarget = ref('');
const imageTagging = ref(false);
const imageHistoryDialogOpen = ref(false);
const imageHistoryLoading = ref(false);
const imageHistoryTitle = ref('');
const imageHistoryItems = ref<DockerImageHistoryItem[]>([]);
const imageRefsDialogOpen = ref(false);
const imageRefsLoading = ref(false);
const imageRefsTitle = ref('');
const imageRefsItems = ref<DockerImageContainerRef[]>([]);

const createContainerForm = ref<DockerCreateContainerPayload>({
  image: '',
  name: '',
  ports: [],
  env: [],
  volumes: [],
  restartPolicy: 'no',
  cmd: [],
  entrypoint: [],
  start: true,
});
const createContainerPortsText = ref('');
const createContainerEnvText = ref('');
const createContainerVolumesText = ref('');
const createContainerCmdText = ref('');
const createContainerEntrypointText = ref('');

const containerStatsMap = ref<Record<string, DockerContainerStats>>({});
const diagnosticMap = ref<Record<string, DockerContainerDiagnostic>>({});

let refreshInterval: number | null = null;
let logsRefreshInterval: number | null = null;
let statsRefreshInterval: number | null = null;

const isConnected = computed(() => sshStore.isConnected && sshStore.sessionId);
const logTailOptions = LOG_TAIL_OPTIONS;

const runningContainers = computed(() => containers.value.filter(c => c.state === 'running'));
const exitedContainers = computed(() => containers.value.filter(c => c.state === 'exited'));
const pausedContainers = computed(() => containers.value.filter(c => c.state === 'paused'));

const selectedContainerSet = computed(() => new Set(selectedContainerIds.value));
const selectedContainers = computed(() =>
  containers.value.filter(container => selectedContainerSet.value.has(container.id))
);
const selectedRunningContainers = computed(() =>
  selectedContainers.value.filter(container => container.state === 'running')
);
const selectedStoppedContainers = computed(() =>
  selectedContainers.value.filter(container => container.state !== 'running')
);

const filteredContainers = computed(() => {
  const nameKeyword = containerNameQuery.value.trim().toLowerCase();
  const imageKeyword = containerImageQuery.value.trim().toLowerCase();

  const list = containers.value.filter((container) => {
    const matchName = !nameKeyword || container.name.toLowerCase().includes(nameKeyword);
    const matchImage = !imageKeyword || container.image.toLowerCase().includes(imageKeyword);
    const matchState =
      containerStateFilter.value === 'all' || container.state === containerStateFilter.value;
    return matchName && matchImage && matchState;
  });

  list.sort((a, b) => {
    let result = 0;
    if (containerSortBy.value === 'createdAt') {
      const aTime = a.createdAt ? new Date(a.createdAt).getTime() : 0;
      const bTime = b.createdAt ? new Date(b.createdAt).getTime() : 0;
      result = aTime - bTime;
    }
    if (containerSortBy.value === 'name') {
      result = a.name.localeCompare(b.name, 'zh-CN');
    }
    if (containerSortBy.value === 'image') {
      result = a.image.localeCompare(b.image, 'zh-CN');
    }
    return containerSortOrder.value === 'asc' ? result : -result;
  });

  return list;
});

const allVisibleContainersSelected = computed(() => {
  if (filteredContainers.value.length === 0) return false;
  return filteredContainers.value.every(container => selectedContainerSet.value.has(container.id));
});

const detailPorts = computed(() => {
  const ports = detailInspect.value?.NetworkSettings?.Ports;
  if (!ports) return [];

  const items: string[] = [];
  for (const [containerPort, mappings] of Object.entries(ports)) {
    if (!mappings || mappings.length === 0) {
      items.push(`${containerPort} -> 未映射`);
      continue;
    }
    for (const mapping of mappings) {
      const hostIp = mapping.HostIp ?? '0.0.0.0';
      const hostPort = mapping.HostPort ?? '-';
      items.push(`${hostIp}:${hostPort} -> ${containerPort}`);
    }
  }
  return items;
});

const detailNetworks = computed(() => {
  const networks = detailInspect.value?.NetworkSettings?.Networks;
  if (!networks) return [];
  return Object.entries(networks).map(([name, info]) => ({
    name,
    ip: info?.IPAddress ?? '-',
  }));
});

const detailStats = computed(() => {
  const containerId = detailContainer.value?.id;
  if (!containerId) return null;
  return getContainerStats(containerId) ?? null;
});

const filteredImages = computed(() => {
  const keyword = imageQuery.value.trim().toLowerCase();

  const list = images.value.filter((image) => {
    const target = `${image.repository}:${image.tag}`.toLowerCase();
    const matchKeyword = !keyword || target.includes(keyword);
    const matchUsage =
      imageUsageFilter.value === 'all'
      || (imageUsageFilter.value === 'dangling' && !!image.dangling)
      || (imageUsageFilter.value === 'unused' && !image.inUse);
    return matchKeyword && matchUsage;
  });

  list.sort((a, b) => {
    let result = 0;
    if (imageSortBy.value === 'createdAt') {
      const aTime = a.createdAt ? new Date(a.createdAt).getTime() : 0;
      const bTime = b.createdAt ? new Date(b.createdAt).getTime() : 0;
      result = aTime - bTime;
    }
    if (imageSortBy.value === 'repository') {
      result = a.repository.localeCompare(b.repository, 'zh-CN');
    }
    if (imageSortBy.value === 'tag') {
      result = a.tag.localeCompare(b.tag, 'zh-CN');
    }
    if (imageSortBy.value === 'size') {
      result = parseImageSizeToBytes(a.size) - parseImageSizeToBytes(b.size);
    }
    return imageSortOrder.value === 'asc' ? result : -result;
  });

  return list;
});

const displayedLogs = computed(() => {
  let value = logsContent.value;

  if (!showLogTimestamps.value) {
    value = value
      .split('\n')
      .map((line) => line.replace(
        /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})\s*/,
        '',
      ))
      .join('\n');
  }

  const keyword = logsKeyword.value.trim().toLowerCase();
  if (!keyword) {
    return value;
  }

  return value
    .split('\n')
    .filter(line => line.toLowerCase().includes(keyword))
    .join('\n');
});

const confirmTitle = computed(() => {
  if (confirmAction.value === 'removeContainer') return '确认删除容器';
  if (confirmAction.value === 'removeImage') return '确认删除镜像';
  if (confirmAction.value === 'pruneDangling') return '确认清理 dangling 镜像';
  if (confirmAction.value === 'pruneUnused') return '确认清理无引用镜像';
  if (confirmAction.value === 'removeStoppedContainers') return '确认删除已停止容器';
  return '确认操作';
});

const confirmButtonText = computed(() => {
  if (confirmAction.value === 'removeContainer' || confirmAction.value === 'removeImage') {
    return '删除';
  }
  return '确认清理';
});

const checkDocker = async () => {
  if (!sshStore.sessionId) return;
  try {
    const result = await dockerApi.checkDocker(sshStore.sessionId);
    dockerAvailable.value = result.available;
  } catch {
    dockerAvailable.value = false;
  }
};

const fetchContainers = async () => {
  if (!sshStore.sessionId) return;
  try {
    containers.value = await dockerApi.listContainers(sshStore.sessionId);
    const visibleIds = new Set(containers.value.map(c => c.id));
    selectedContainerIds.value = selectedContainerIds.value.filter(id => visibleIds.has(id));
    await Promise.all([
      refreshContainerDiagnostics(),
      refreshContainerStats(),
    ]);
  } catch {
    toast.error('获取容器列表失败');
  }
};

const refreshContainerDiagnostics = async () => {
  if (!sshStore.sessionId || containers.value.length === 0) {
    diagnosticMap.value = {};
    return;
  }

  try {
    const diagnostics = await dockerApi.getContainerDiagnostics(
      sshStore.sessionId,
      containers.value.map(container => container.id),
    );
    diagnosticMap.value = diagnostics.reduce<Record<string, DockerContainerDiagnostic>>((acc, item) => {
      acc[item.containerId] = item;
      return acc;
    }, {});
  } catch {
    diagnosticMap.value = {};
  }
};

const refreshContainerStats = async () => {
  if (!sshStore.sessionId || containers.value.length === 0) {
    containerStatsMap.value = {};
    return;
  }

  const next: Record<string, DockerContainerStats> = {};
  await Promise.all(
    containers.value.map(async (container) => {
      try {
        const stats = await dockerApi.getContainerStats(sshStore.sessionId!, container.id);
        next[container.id] = stats;
      } catch {
        // ignore single container stats errors
      }
    })
  );
  containerStatsMap.value = next;
};

const getContainerStats = (containerId: string) => containerStatsMap.value[containerId];
const getContainerDiagnostic = (containerId: string) => diagnosticMap.value[containerId];

const isFrequentRestart = (containerId: string) => {
  const restartCount = getContainerDiagnostic(containerId)?.restartCount ?? 0;
  return restartCount >= 3;
};

const isUnhealthyContainer = (containerId: string) => {
  return getContainerDiagnostic(containerId)?.healthStatus === 'unhealthy';
};

const isExitedAbnormally = (container: DockerContainer) => {
  if (container.state !== 'exited') return false;
  const exitCode = getContainerDiagnostic(container.id)?.exitCode ?? 0;
  return exitCode !== 0;
};

const openContainerDetail = async (container: DockerContainer) => {
  if (!sshStore.sessionId) return;
  detailContainer.value = container;
  detailDialogOpen.value = true;
  detailLoading.value = true;

  try {
    detailInspect.value = await dockerApi.inspectContainer(sshStore.sessionId, container.id);
  } catch {
    detailInspect.value = null;
    toast.error('获取容器详情失败');
  } finally {
    detailLoading.value = false;
  }
};

const fetchImages = async () => {
  if (!sshStore.sessionId) return;
  try {
    images.value = await dockerApi.listImages(sshStore.sessionId);
  } catch {
    toast.error('获取镜像列表失败');
  }
};

const refresh = async () => {
  if (!sshStore.sessionId || refreshing.value) return;
  refreshing.value = true;

  await checkDocker();
  if (dockerAvailable.value) {
    if (activeTab.value === 'containers') {
      await fetchContainers();
    } else {
      await fetchImages();
    }
  }

  refreshing.value = false;
};

const startContainer = async (container: DockerContainer) => {
  if (!sshStore.sessionId) return;
  try {
    await dockerApi.startContainer(sshStore.sessionId, container.id);
    toast.success(`容器 ${container.name} 已启动`);
    await fetchContainers();
  } catch {
    toast.error('启动容器失败');
  }
};

const stopContainer = async (container: DockerContainer) => {
  if (!sshStore.sessionId) return;
  try {
    await dockerApi.stopContainer(sshStore.sessionId, container.id);
    toast.success(`容器 ${container.name} 已停止`);
    await fetchContainers();
  } catch {
    toast.error('停止容器失败');
  }
};

const restartContainer = async (container: DockerContainer) => {
  if (!sshStore.sessionId) return;
  try {
    await dockerApi.restartContainer(sshStore.sessionId, container.id);
    toast.success(`容器 ${container.name} 已重启`);
    await fetchContainers();
  } catch {
    toast.error('重启容器失败');
  }
};

const pauseContainer = async (container: DockerContainer) => {
  if (!sshStore.sessionId) return;
  try {
    await dockerApi.pauseContainer(sshStore.sessionId, container.id);
    toast.success(`容器 ${container.name} 已暂停`);
    await fetchContainers();
  } catch {
    toast.error('暂停容器失败');
  }
};

const unpauseContainer = async (container: DockerContainer) => {
  if (!sshStore.sessionId) return;
  try {
    await dockerApi.unpauseContainer(sshStore.sessionId, container.id);
    toast.success(`容器 ${container.name} 已恢复`);
    await fetchContainers();
  } catch {
    toast.error('恢复容器失败');
  }
};

const openRenameDialog = (container: DockerContainer) => {
  renamingContainerId.value = container.id;
  renamingContainerName.value = container.name;
  renameDialogOpen.value = true;
};

const submitRenameContainer = async () => {
  if (!sshStore.sessionId || !renamingContainerId.value) return;
  const newName = renamingContainerName.value.trim();
  if (!newName) {
    toast.error('请输入新容器名称');
    return;
  }

  renamingContainer.value = true;
  try {
    await dockerApi.renameContainer(
      sshStore.sessionId,
      renamingContainerId.value,
      newName,
    );
    toast.success('容器重命名成功');
    renameDialogOpen.value = false;
    await fetchContainers();
  } catch {
    toast.error('容器重命名失败');
  } finally {
    renamingContainer.value = false;
  }
};

const recreateContainer = async (container: DockerContainer) => {
  if (!sshStore.sessionId) return;
  recreateLoadingId.value = container.id;
  try {
    const result = await dockerApi.recreateContainer(sshStore.sessionId, container.id);
    toast.success(`容器 ${result.name} 重建完成`);
    await fetchContainers();
  } catch {
    toast.error('容器重建失败');
  } finally {
    recreateLoadingId.value = null;
  }
};

const toLineList = (value: string) => {
  return value
    .split('\n')
    .map(item => item.trim())
    .filter(item => item.length > 0);
};

const openCreateContainerDialog = () => {
  createContainerForm.value = {
    image: '',
    name: '',
    ports: [],
    env: [],
    volumes: [],
    restartPolicy: 'no',
    cmd: [],
    entrypoint: [],
    start: true,
  };
  createContainerPortsText.value = '';
  createContainerEnvText.value = '';
  createContainerVolumesText.value = '';
  createContainerCmdText.value = '';
  createContainerEntrypointText.value = '';
  createDialogOpen.value = true;
};

const submitCreateContainer = async () => {
  if (!sshStore.sessionId) return;
  const image = createContainerForm.value.image?.trim() ?? '';
  if (!image) {
    toast.error('镜像名称不能为空');
    return;
  }

  creatingContainer.value = true;
  try {
    const payload: DockerCreateContainerPayload = {
      image,
      name: createContainerForm.value.name?.trim() || undefined,
      ports: toLineList(createContainerPortsText.value),
      env: toLineList(createContainerEnvText.value),
      volumes: toLineList(createContainerVolumesText.value),
      restartPolicy: createContainerForm.value.restartPolicy || 'no',
      cmd: toLineList(createContainerCmdText.value),
      entrypoint: toLineList(createContainerEntrypointText.value),
      start: createContainerForm.value.start === true,
    };
    const result = await dockerApi.createContainer(sshStore.sessionId, payload);
    toast.success(`容器创建成功：${shortId(result.containerId)}`);
    createDialogOpen.value = false;
    await fetchContainers();
  } catch {
    toast.error('创建容器失败');
  } finally {
    creatingContainer.value = false;
  }
};

const openImagePullDialog = () => {
  imagePullInput.value = '';
  imagePullDialogOpen.value = true;
};

const submitPullImage = async () => {
  if (!sshStore.sessionId) return;
  const image = imagePullInput.value.trim();
  if (!image) {
    toast.error('请输入镜像名称');
    return;
  }

  imagePulling.value = true;
  try {
    await dockerApi.pullImage(sshStore.sessionId, image);
    toast.success('镜像拉取成功');
    imagePullDialogOpen.value = false;
    await fetchImages();
  } catch {
    toast.error('镜像拉取失败');
  } finally {
    imagePulling.value = false;
  }
};

const openImageTagDialog = (image: DockerImage) => {
  imageTagSource.value = `${image.repository}:${image.tag}`;
  imageTagTarget.value = '';
  imageTagDialogOpen.value = true;
};

const submitTagImage = async () => {
  if (!sshStore.sessionId) return;
  const sourceImage = imageTagSource.value.trim();
  const targetImage = imageTagTarget.value.trim();
  if (!sourceImage || !targetImage) {
    toast.error('源镜像和目标标签都不能为空');
    return;
  }

  imageTagging.value = true;
  try {
    await dockerApi.tagImage(sshStore.sessionId, sourceImage, targetImage);
    toast.success('镜像重新打标签成功');
    imageTagDialogOpen.value = false;
    await fetchImages();
  } catch {
    toast.error('镜像重新打标签失败');
  } finally {
    imageTagging.value = false;
  }
};

const viewImageHistory = async (image: DockerImage) => {
  if (!sshStore.sessionId) return;
  imageHistoryDialogOpen.value = true;
  imageHistoryLoading.value = true;
  imageHistoryTitle.value = `${image.repository}:${image.tag}`;
  imageHistoryItems.value = [];

  try {
    imageHistoryItems.value = await dockerApi.getImageHistory(sshStore.sessionId, image.id);
  } catch {
    toast.error('获取镜像历史失败');
  } finally {
    imageHistoryLoading.value = false;
  }
};

const viewImageRefs = async (image: DockerImage) => {
  if (!sshStore.sessionId) return;
  imageRefsDialogOpen.value = true;
  imageRefsLoading.value = true;
  imageRefsTitle.value = `${image.repository}:${image.tag}`;
  imageRefsItems.value = [];

  try {
    imageRefsItems.value = await dockerApi.getImageContainers(sshStore.sessionId, image.id);
  } catch {
    toast.error('获取镜像引用容器失败');
  } finally {
    imageRefsLoading.value = false;
  }
};

const openRawInspect = () => {
  if (!detailInspect.value) {
    toast.error('暂无 inspect 数据');
    return;
  }
  rawInspectDialogOpen.value = true;
};

const rawInspectText = computed(() => {
  if (!detailInspect.value) return '';
  return JSON.stringify(detailInspect.value, null, 2);
});

const downloadInspectConfig = () => {
  if (!detailInspect.value || !detailContainer.value) {
    toast.error('暂无可导出的容器配置');
    return;
  }

  const text = JSON.stringify(detailInspect.value, null, 2);
  const filename = `${detailContainer.value.name || 'container'}-inspect.json`;
  const blob = new Blob([text], { type: 'application/json;charset=utf-8' });
  const url = window.URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  window.URL.revokeObjectURL(url);
};

const toggleContainerSelection = (id: string) => {
  if (selectedContainerSet.value.has(id)) {
    selectedContainerIds.value = selectedContainerIds.value.filter(item => item !== id);
    return;
  }
  selectedContainerIds.value = [...selectedContainerIds.value, id];
};

const toggleSelectAllVisibleContainers = (event: Event) => {
  const checked = (event.target as HTMLInputElement).checked;
  if (!checked) {
    const visibleIdSet = new Set(filteredContainers.value.map(item => item.id));
    selectedContainerIds.value = selectedContainerIds.value.filter(id => !visibleIdSet.has(id));
    return;
  }

  const merged = new Set(selectedContainerIds.value);
  for (const container of filteredContainers.value) {
    merged.add(container.id);
  }
  selectedContainerIds.value = Array.from(merged);
};

const clearSelectedContainers = () => {
  selectedContainerIds.value = [];
};

const batchStartSelected = async () => {
  if (!sshStore.sessionId) return;
  const ids = selectedStoppedContainers.value.map(container => container.id);
  if (ids.length === 0) {
    toast.info('请选择未运行容器');
    return;
  }

  batchProcessing.value = true;
  try {
    const result = await dockerApi.batchStartContainers(sshStore.sessionId, ids);
    toast.success(`批量启动完成，共处理 ${result.processed} 个容器`);
    await fetchContainers();
  } catch {
    toast.error('批量启动失败');
  } finally {
    batchProcessing.value = false;
  }
};

const batchStopSelected = async () => {
  if (!sshStore.sessionId) return;
  const ids = selectedRunningContainers.value.map(container => container.id);
  if (ids.length === 0) {
    toast.info('请选择运行中容器');
    return;
  }

  batchProcessing.value = true;
  try {
    const result = await dockerApi.batchStopContainers(sshStore.sessionId, ids);
    toast.success(`批量停止完成，共处理 ${result.processed} 个容器`);
    await fetchContainers();
  } catch {
    toast.error('批量停止失败');
  } finally {
    batchProcessing.value = false;
  }
};

const showRemoveContainerConfirm = (container: DockerContainer) => {
  confirmAction.value = 'removeContainer';
  confirmItem.value = container;
  confirmForce.value = container.state === 'running';
  confirmDialogOpen.value = true;
};

const showRemoveImageConfirm = (image: DockerImage) => {
  confirmAction.value = 'removeImage';
  confirmItem.value = image;
  confirmForce.value = false;
  confirmDialogOpen.value = true;
};

const showRemoveStoppedContainersConfirm = () => {
  confirmAction.value = 'removeStoppedContainers';
  confirmItem.value = null;
  confirmForce.value = false;
  confirmDialogOpen.value = true;
};

const showPruneDanglingConfirm = () => {
  confirmAction.value = 'pruneDangling';
  confirmItem.value = null;
  confirmForce.value = false;
  confirmDialogOpen.value = true;
};

const showPruneUnusedConfirm = () => {
  confirmAction.value = 'pruneUnused';
  confirmItem.value = null;
  confirmForce.value = false;
  confirmDialogOpen.value = true;
};

const confirmRemove = async () => {
  if (!sshStore.sessionId || !confirmAction.value) return;

  try {
    if (confirmAction.value === 'removeContainer' && confirmItem.value) {
      await dockerApi.removeContainer(sshStore.sessionId, confirmItem.value.id, confirmForce.value);
      toast.success('容器已删除');
      await fetchContainers();
    }

    if (confirmAction.value === 'removeImage' && confirmItem.value) {
      await dockerApi.removeImage(sshStore.sessionId, confirmItem.value.id, confirmForce.value);
      toast.success('镜像已删除');
      await fetchImages();
    }

    if (confirmAction.value === 'removeStoppedContainers') {
      const result = await dockerApi.removeStoppedContainers(sshStore.sessionId);
      toast.success(`已删除 ${result.removedCount} 个已停止容器`);
      await fetchContainers();
    }

    if (confirmAction.value === 'pruneDangling') {
      await dockerApi.pruneImages(sshStore.sessionId, false);
      toast.success('dangling 镜像清理完成');
      await fetchImages();
    }

    if (confirmAction.value === 'pruneUnused') {
      await dockerApi.pruneImages(sshStore.sessionId, true);
      toast.success('无引用镜像清理完成');
      await fetchImages();
    }
  } catch {
    toast.error('操作失败');
  }

  confirmDialogOpen.value = false;
  confirmItem.value = null;
  confirmAction.value = null;
};

const refreshLogs = async (silent = false) => {
  if (!sshStore.sessionId || !logsContainer.value) return;

  if (silent) {
    logsRefreshing.value = true;
  } else {
    logsLoading.value = true;
  }

  try {
    const result = await dockerApi.getContainerLogsAdvanced(
      sshStore.sessionId,
      logsContainer.value.id,
      {
        tail: logsTail.value,
        timestamps: true,
      },
    );
    logsContent.value = result.logs;
    logsLastUpdatedAt.value = new Date();
  } catch {
    toast.error('获取日志失败');
    if (!silent) {
      logsContent.value = '';
    }
  } finally {
    logsLoading.value = false;
    logsRefreshing.value = false;
  }
};

const syncLogsAutoRefresh = () => {
  if (logsRefreshInterval) {
    clearInterval(logsRefreshInterval);
    logsRefreshInterval = null;
  }

  if (logsDialogOpen.value && logsAutoRefresh.value) {
    logsRefreshInterval = window.setInterval(() => {
      void refreshLogs(true);
    }, 4000);
  }
};

const viewLogs = async (container: DockerContainer) => {
  if (!sshStore.sessionId) return;
  logsContainer.value = container;
  logsDialogOpen.value = true;
  await refreshLogs();
};

const copyLogs = async () => {
  try {
    await navigator.clipboard.writeText(displayedLogs.value);
    toast.success('日志已复制到剪贴板');
  } catch {
    toast.error('复制日志失败');
  }
};

const downloadLogs = () => {
  const text = displayedLogs.value;
  const filename = `${logsContainer.value?.name ?? 'container'}-${Date.now()}.log`;
  const blob = new Blob([text], { type: 'text/plain;charset=utf-8' });
  const url = window.URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  window.URL.revokeObjectURL(url);
};

const enterShell = async (container: DockerContainer) => {
  if (!sshStore.sessionId) return;
  if (container.state !== 'running') {
    toast.error('容器未运行，无法进入 Shell');
    return;
  }

  try {
    const res = await dockerApi.createContainerShellSession(sshStore.sessionId, container.id);
    desktopStore.openWindow('terminal', {
      title: `Shell: ${container.name}`,
      sessionId: res.sessionId,
    });
  } catch {
    toast.error('进入容器 Shell 失败');
  }
};

const formatDate = (dateStr?: string) => {
  if (!dateStr) return '-';
  const date = new Date(dateStr);
  if (Number.isNaN(date.getTime())) return '-';
  return date.toLocaleString('zh-CN');
};

const shortId = (id: string) => id.substring(0, 12);

const copyToClipboard = async (text: string) => {
  try {
    await navigator.clipboard.writeText(text);
    toast.success('已复制到剪贴板');
  } catch {
    toast.error('复制失败');
  }
};

const parsePort = (portStr: string) => {
  const match = portStr.match(/^(.*):(\d+)->(\d+)\/(tcp|udp)$/);
  if (match) {
    return {
      host: match[1],
      hostPort: match[2],
      containerPort: match[3],
      protocol: match[4],
      raw: portStr,
    };
  }
  return { raw: portStr };
};

const getPortDisplay = (portStr: string) => {
  if (!portStr) return '-';
  const parsed = parsePort(portStr);
  if (parsed.hostPort && parsed.containerPort) {
    return `${parsed.hostPort}:${parsed.containerPort}`;
  }
  return portStr;
};

const parseImageSizeToBytes = (size: string) => {
  const match = size.trim().match(/^(\d+(?:\.\d+)?)\s*([KMGTP]?B)$/i);
  if (!match) return 0;

  const valueRaw = match[1];
  const unitRaw = match[2];
  if (!valueRaw || !unitRaw) return 0;

  const value = Number(valueRaw);
  const unit = unitRaw.toUpperCase();
  const units: Record<string, number> = {
    B: 1,
    KB: 1024,
    MB: 1024 ** 2,
    GB: 1024 ** 3,
    TB: 1024 ** 4,
    PB: 1024 ** 5,
  };

  return value * (units[unit] ?? 1);
};

onMounted(async () => {
  if (isConnected.value) {
    loading.value = true;
    await checkDocker();
    if (dockerAvailable.value) {
      await fetchContainers();
    }
    loading.value = false;

    refreshInterval = window.setInterval(() => {
      if (activeTab.value === 'containers' && !confirmDialogOpen.value && !detailDialogOpen.value) {
        void fetchContainers();
      }
    }, 10000);

    statsRefreshInterval = window.setInterval(() => {
      if (activeTab.value === 'containers' && !detailDialogOpen.value) {
        void Promise.all([
          refreshContainerDiagnostics(),
          refreshContainerStats(),
        ]);
      }
    }, 12000);
  }
});

onUnmounted(() => {
  if (refreshInterval) {
    clearInterval(refreshInterval);
    refreshInterval = null;
  }
  if (logsRefreshInterval) {
    clearInterval(logsRefreshInterval);
    logsRefreshInterval = null;
  }
  if (statsRefreshInterval) {
    clearInterval(statsRefreshInterval);
    statsRefreshInterval = null;
  }
});

watch(activeTab, async (newTab) => {
  if (newTab === 'images' && images.value.length === 0) {
    await fetchImages();
  }
});

watch(() => sshStore.sessionId, async (newSessionId) => {
  if (newSessionId) {
    loading.value = true;
    await checkDocker();
    if (dockerAvailable.value) {
      await fetchContainers();
    }
    loading.value = false;
  } else {
    containers.value = [];
    images.value = [];
    selectedContainerIds.value = [];
    containerStatsMap.value = {};
    diagnosticMap.value = {};
    detailInspect.value = null;
    detailContainer.value = null;
    detailDialogOpen.value = false;
    dockerAvailable.value = null;
  }
});

watch([logsDialogOpen, logsAutoRefresh], () => {
  syncLogsAutoRefresh();
});

watch(logsTail, async (newValue, oldValue) => {
  if (newValue !== oldValue && logsDialogOpen.value) {
    await refreshLogs();
  }
});

watch(logsDialogOpen, (open) => {
  if (!open) {
    logsAutoRefresh.value = false;
    logsKeyword.value = '';
    showLogTimestamps.value = true;
    logsLastUpdatedAt.value = null;
  }
});

watch(detailDialogOpen, (open) => {
  if (!open) {
    detailInspect.value = null;
    detailContainer.value = null;
    detailLoading.value = false;
  }
});
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

      <div v-else-if="activeTab === 'containers'" class="space-y-4">
        <div class="grid grid-cols-4 gap-4">
          <button class="bg-muted/50 rounded-lg p-4 text-left transition-colors hover:bg-muted"
            :class="containerStateFilter === 'all' ? 'ring-1 ring-primary' : ''"
            @click="containerStateFilter = 'all'">
            <div class="text-sm text-muted-foreground">总容器数</div>
            <div class="text-2xl font-bold">{{ containers.length }}</div>
          </button>
          <button class="bg-muted/50 rounded-lg p-4 text-left transition-colors hover:bg-muted"
            :class="containerStateFilter === 'running' ? 'ring-1 ring-primary' : ''"
            @click="containerStateFilter = 'running'">
            <div class="text-sm text-muted-foreground">运行中</div>
            <div class="text-2xl font-bold text-green-600">{{ runningContainers.length }}</div>
          </button>
          <button class="bg-muted/50 rounded-lg p-4 text-left transition-colors hover:bg-muted"
            :class="containerStateFilter === 'exited' ? 'ring-1 ring-primary' : ''"
            @click="containerStateFilter = 'exited'">
            <div class="text-sm text-muted-foreground">已停止</div>
            <div class="text-2xl font-bold text-gray-500">{{ exitedContainers.length }}</div>
          </button>
          <button class="bg-muted/50 rounded-lg p-4 text-left transition-colors hover:bg-muted"
            :class="containerStateFilter === 'paused' ? 'ring-1 ring-primary' : ''"
            @click="containerStateFilter = 'paused'">
            <div class="text-sm text-muted-foreground">已暂停</div>
            <div class="text-2xl font-bold text-yellow-600">{{ pausedContainers.length }}</div>
          </button>
        </div>

        <div class="border rounded-lg p-3 bg-muted/20 space-y-3">
          <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-6 gap-3">
            <Input v-model="containerNameQuery" placeholder="搜索容器名称"/>
            <Input v-model="containerImageQuery" placeholder="搜索镜像名称"/>

            <select v-model="containerStateFilter"
              class="h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring">
              <option value="all">状态：全部</option>
              <option value="running">状态：running</option>
              <option value="exited">状态：exited</option>
              <option value="paused">状态：paused</option>
            </select>

            <select v-model="containerSortBy"
              class="h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring">
              <option value="createdAt">排序：创建时间</option>
              <option value="name">排序：名称</option>
              <option value="image">排序：镜像</option>
            </select>

            <select v-model="containerSortOrder"
              class="h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring">
              <option value="desc">顺序：降序</option>
              <option value="asc">顺序：升序</option>
            </select>

            <Button variant="outline" :disabled="!selectedContainerIds.length" @click="clearSelectedContainers">
              清空选择（{{ selectedContainerIds.length }}）
            </Button>
          </div>

          <div class="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" :disabled="batchProcessing || !selectedStoppedContainers.length"
              @click="batchStartSelected">
              <Play class="w-4 h-4"/>
              批量启动（{{ selectedStoppedContainers.length }}）
            </Button>
            <Button size="sm" variant="outline" :disabled="batchProcessing || !selectedRunningContainers.length"
              @click="batchStopSelected">
              <Square class="w-4 h-4"/>
              批量停止（{{ selectedRunningContainers.length }}）
            </Button>
            <Button size="sm" variant="outline" :disabled="batchProcessing" @click="showRemoveStoppedContainersConfirm">
              <Trash2 class="w-4 h-4 text-red-600"/>
              删除全部已停止容器
            </Button>
          </div>
        </div>

        <div class="border rounded-lg overflow-hidden">
          <div class="max-h-[calc(100vh-280px)] overflow-auto custom-scrollbar">
            <Table>
              <TableHeader class="sticky top-0 bg-background z-10">
                <TableRow class="bg-muted/50">
                  <TableHead class="w-10 text-center">
                    <input
                      type="checkbox"
                      :checked="allVisibleContainersSelected"
                      @change="toggleSelectAllVisibleContainers"
                    >
                  </TableHead>
                  <TableHead class="w-24">ID</TableHead>
                  <TableHead>名称</TableHead>
                  <TableHead>镜像</TableHead>
                  <TableHead>状态</TableHead>
                  <TableHead class="w-32">端口</TableHead>
                  <TableHead class="w-44">资源</TableHead>
                  <TableHead class="w-32">创建时间</TableHead>
                  <TableHead class="w-48 text-right">操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                <TableRow v-if="filteredContainers.length === 0">
                  <TableCell colspan="9" class="text-center text-muted-foreground py-8">
                    暂无容器
                  </TableCell>
                </TableRow>
                <TableRow
                  v-for="container in filteredContainers"
                  :key="container.id"
                  :class="selectedContainerSet.has(container.id) ? 'bg-muted/30' : ''"
                >
                  <TableCell class="text-center">
                    <input
                      type="checkbox"
                      :checked="selectedContainerSet.has(container.id)"
                      @change="toggleContainerSelection(container.id)"
                    >
                  </TableCell>
                  <TableCell class="font-mono text-xs">{{ shortId(container.id) }}</TableCell>
                  <TableCell class="font-medium">{{ container.name }}</TableCell>
                  <TableCell class="text-muted-foreground">{{ container.image }}</TableCell>
                  <TableCell>
                    <div class="flex flex-wrap items-center gap-1">
                      <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium" :class="{
                        'bg-green-100 text-green-800': container.state === 'running',
                        'bg-gray-100 text-gray-800': container.state === 'exited',
                          'bg-yellow-100 text-yellow-800': container.state === 'paused',
                          'bg-red-100 text-red-800': !['running', 'exited', 'paused'].includes(container.state)
                        }">
                        {{ container.state }}
                      </span>
                      <span
                        v-if="isUnhealthyContainer(container.id)"
                        class="inline-flex items-center rounded-full px-2 py-0.5 text-xs bg-red-100 text-red-700"
                      >unhealthy</span>
                      <span
                        v-if="isFrequentRestart(container.id)"
                        class="inline-flex items-center rounded-full px-2 py-0.5 text-xs bg-amber-100 text-amber-700"
                      >频繁重启</span>
                      <span
                        v-if="isExitedAbnormally(container)"
                        class="inline-flex items-center rounded-full px-2 py-0.5 text-xs bg-rose-100 text-rose-700"
                      >异常退出</span>
                    </div>
                  </TableCell>
                  <TableCell class="text-xs">
                    <TooltipProvider v-if="container.ports.length">
                      <Tooltip>
                        <TooltipTrigger as-child>
                          <div class="flex flex-wrap gap-1 cursor-pointer">
                            <span v-for="port in container.ports.slice(0, 3)" :key="port"
                              class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-blue-50 text-blue-700 border border-blue-200 dark:bg-blue-900/30 dark:text-blue-300 dark:border-blue-800">
                              {{ getPortDisplay(port) }}
                            </span>
                            <span v-if="container.ports.length > 3"
                              class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-400">
                              +{{ container.ports.length - 3 }}
                            </span>
                          </div>
                        </TooltipTrigger>
                        <TooltipContent class="max-w-xs">
                          <div class="space-y-2">
                            <div class="text-xs font-semibold">端口映射</div>
                            <div class="space-y-1">
                              <div v-for="port in container.ports" :key="port"
                                class="flex items-center justify-between gap-3 text-xs group cursor-pointer hover:bg-primary-foreground/10 rounded px-1 -mx-1 py-0.5 transition-colors"
                                @click="copyToClipboard(port)">
                                <code class="bg-primary-foreground/20 px-1.5 py-0.5 rounded font-mono">{{ port }}</code>
                                <span class="opacity-0 group-hover:opacity-100 transition-opacity text-[10px]">点击复制</span>
                              </div>
                            </div>
                          </div>
                        </TooltipContent>
                      </Tooltip>
                    </TooltipProvider>
                    <div v-else class="flex items-center justify-center w-8 h-6 rounded bg-gray-100 dark:bg-gray-800">
                      <span class="text-xs text-gray-400">-</span>
                    </div>
                  </TableCell>
                  <TableCell class="text-xs">
                    <div class="space-y-1">
                      <div>
                        CPU:
                        <span class="font-medium">{{ getContainerStats(container.id)?.cpuPercent || '-' }}</span>
                      </div>
                      <div>
                        内存:
                        <span class="font-medium">{{ getContainerStats(container.id)?.memPercent || '-' }}</span>
                      </div>
                    </div>
                  </TableCell>
                  <TableCell class="text-xs text-muted-foreground">
                    {{ formatDate(container.createdAt) }}
                  </TableCell>
                  <TableCell class="text-right">
                    <div class="flex items-center justify-end gap-1">
                      <Button variant="ghost" size="icon" class="h-8 w-8" @click="openContainerDetail(container)">
                        <Info class="w-4 h-4 text-blue-600"/>
                      </Button>
                      <Button v-if="container.state !== 'running'" variant="ghost" size="icon" class="h-8 w-8"
                        @click="startContainer(container)">
                        <Play class="w-4 h-4 text-green-600"/>
                      </Button>
                      <Button v-if="container.state === 'running'" variant="ghost" size="icon" class="h-8 w-8"
                        @click="stopContainer(container)">
                        <Square class="w-4 h-4 text-amber-600"/>
                      </Button>
                      <Button variant="ghost" size="icon" class="h-8 w-8" @click="restartContainer(container)">
                        <RotateCw class="w-4 h-4"/>
                      </Button>
                      <Button
                        v-if="container.state === 'running'"
                        variant="ghost"
                        size="icon"
                        class="h-8 w-8"
                        @click="pauseContainer(container)"
                      >
                        <Pause class="w-4 h-4 text-yellow-600"/>
                      </Button>
                      <Button
                        v-if="container.state === 'paused'"
                        variant="ghost"
                        size="icon"
                        class="h-8 w-8"
                        @click="unpauseContainer(container)"
                      >
                        <Play class="w-4 h-4 text-green-600"/>
                      </Button>
                      <Button variant="ghost" size="icon" class="h-8 w-8" @click="viewLogs(container)">
                        <FileText class="w-4 h-4"/>
                      </Button>
                      <Button variant="ghost" size="icon" class="h-8 w-8" @click="openRenameDialog(container)">
                        <Pencil class="w-4 h-4 text-sky-600"/>
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        class="h-8 w-8"
                        :disabled="recreateLoadingId === container.id"
                        @click="recreateContainer(container)"
                      >
                        <RefreshCw class="w-4 h-4 text-indigo-600" :class="{ 'animate-spin': recreateLoadingId === container.id }"/>
                      </Button>
                      <Button variant="ghost" size="icon" class="h-8 w-8" :disabled="container.state !== 'running'"
                        @click="enterShell(container)">
                        <Terminal class="w-4 h-4"/>
                      </Button>
                      <Button variant="ghost" size="icon" class="h-8 w-8" @click="showRemoveContainerConfirm(container)">
                        <Trash2 class="w-4 h-4 text-red-600"/>
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>
        </div>
      </div>

      <div v-else-if="activeTab === 'images'" class="space-y-4">
        <div class="border rounded-lg p-3 bg-muted/20 space-y-3">
          <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-6 gap-3">
            <Input v-model="imageQuery" placeholder="搜索仓库或标签"/>

            <select v-model="imageUsageFilter"
              class="h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring">
              <option value="all">镜像类型：全部</option>
              <option value="dangling">仅 dangling 镜像</option>
              <option value="unused">仅无引用镜像</option>
            </select>

            <select v-model="imageSortBy"
              class="h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring">
              <option value="createdAt">排序：创建时间</option>
              <option value="repository">排序：仓库</option>
              <option value="tag">排序：标签</option>
              <option value="size">排序：大小</option>
            </select>

            <select v-model="imageSortOrder"
              class="h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring">
              <option value="desc">顺序：降序</option>
              <option value="asc">顺序：升序</option>
            </select>

            <Button size="sm" variant="outline" @click="showPruneDanglingConfirm">
              清理 dangling 镜像
            </Button>
            <Button size="sm" variant="outline" @click="showPruneUnusedConfirm">
              清理无引用镜像
            </Button>
          </div>
        </div>

        <div class="border rounded-lg overflow-hidden">
          <div class="max-h-[calc(100vh-240px)] overflow-auto custom-scrollbar">
            <Table>
              <TableHeader class="sticky top-0 bg-background z-10">
                <TableRow class="bg-muted/50">
                  <TableHead class="w-24">ID</TableHead>
                  <TableHead>仓库</TableHead>
                  <TableHead>标签</TableHead>
                  <TableHead>大小</TableHead>
                  <TableHead class="w-40">识别</TableHead>
                  <TableHead class="w-32">创建时间</TableHead>
                  <TableHead class="w-52 text-right">操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                <TableRow v-if="filteredImages.length === 0">
                  <TableCell colspan="7" class="text-center text-muted-foreground py-8">
                    暂无镜像
                  </TableCell>
                </TableRow>
                <TableRow v-for="image in filteredImages" :key="image.id">
                  <TableCell class="font-mono text-xs">{{ shortId(image.id) }}</TableCell>
                  <TableCell class="font-medium">{{ image.repository }}</TableCell>
                  <TableCell>
                    <span class="inline-flex items-center rounded-md border px-2 py-0.5 text-xs font-medium">
                      {{ image.tag }}
                    </span>
                  </TableCell>
                  <TableCell class="text-muted-foreground">{{ image.size }}</TableCell>
                  <TableCell>
                    <div class="flex items-center gap-2">
                      <span v-if="image.dangling" class="inline-flex items-center rounded-full px-2 py-0.5 text-xs bg-amber-100 text-amber-700">
                        dangling
                      </span>
                      <span v-if="!image.inUse" class="inline-flex items-center rounded-full px-2 py-0.5 text-xs bg-gray-100 text-gray-700">
                        unused
                      </span>
                      <span v-if="!image.dangling && image.inUse" class="inline-flex items-center rounded-full px-2 py-0.5 text-xs bg-green-100 text-green-700">
                        in-use
                      </span>
                    </div>
                  </TableCell>
                  <TableCell class="text-xs text-muted-foreground">
                    {{ formatDate(image.createdAt) }}
                  </TableCell>
                  <TableCell class="text-right">
                    <div class="flex items-center justify-end gap-1">
                      <Button variant="ghost" size="icon" class="h-8 w-8" @click="viewImageHistory(image)">
                        <Info class="w-4 h-4 text-blue-600"/>
                      </Button>
                      <Button variant="ghost" size="icon" class="h-8 w-8" @click="viewImageRefs(image)">
                        <Container class="w-4 h-4 text-teal-600"/>
                      </Button>
                      <Button variant="ghost" size="icon" class="h-8 w-8" @click="openImageTagDialog(image)">
                        <Tag class="w-4 h-4 text-indigo-600"/>
                      </Button>
                      <Button variant="ghost" size="icon" class="h-8 w-8" @click="showRemoveImageConfirm(image)">
                        <Trash2 class="w-4 h-4 text-red-600"/>
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>
        </div>
      </div>
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
            基础创建参数（按行填写映射项）
          </DialogDescription>
        </DialogHeader>
        <div class="flex-1 overflow-auto custom-scrollbar pr-1 space-y-3">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">镜像</div>
              <Input v-model="createContainerForm.image" placeholder="nginx:latest"/>
            </div>
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">容器名称（可选）</div>
              <Input v-model="createContainerForm.name" placeholder="my-nginx"/>
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">端口映射（每行一条，如 8080:80）</div>
              <textarea v-model="createContainerPortsText" class="w-full min-h-24 rounded-md border bg-background px-3 py-2 text-sm"></textarea>
            </div>
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">环境变量（每行一条，如 KEY=VALUE）</div>
              <textarea v-model="createContainerEnvText" class="w-full min-h-24 rounded-md border bg-background px-3 py-2 text-sm"></textarea>
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">卷挂载（每行一条，如 /data:/app/data）</div>
              <textarea v-model="createContainerVolumesText" class="w-full min-h-24 rounded-md border bg-background px-3 py-2 text-sm"></textarea>
            </div>
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">Restart Policy</div>
              <select
                v-model="createContainerForm.restartPolicy"
                class="h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              >
                <option value="no">no</option>
                <option value="always">always</option>
                <option value="unless-stopped">unless-stopped</option>
                <option value="on-failure">on-failure</option>
              </select>
              <label class="inline-flex items-center gap-2 text-sm mt-2">
                <input v-model="createContainerForm.start" type="checkbox">
                创建后自动启动
              </label>
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">Entrypoint（每行一个参数）</div>
              <textarea v-model="createContainerEntrypointText" class="w-full min-h-20 rounded-md border bg-background px-3 py-2 text-sm"></textarea>
            </div>
            <div class="space-y-1">
              <div class="text-sm text-muted-foreground">命令 CMD（每行一个参数）</div>
              <textarea v-model="createContainerCmdText" class="w-full min-h-20 rounded-md border bg-background px-3 py-2 text-sm"></textarea>
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

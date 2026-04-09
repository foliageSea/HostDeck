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

type ConfirmAction =
  | 'removeContainer'
  | 'removeImage'
  | 'pruneDangling'
  | 'pruneUnused'
  | 'removeStoppedContainers';

const LOG_TAIL_OPTIONS = [100, 200, 500, 1000] as const;
type LogTailOption = (typeof LOG_TAIL_OPTIONS)[number];

export const useDockerPageState = () => {
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
  const createContainerPorts = ref<string[]>(['']);
  const createContainerEnvs = ref<string[]>(['']);
  const createContainerVolumes = ref<string[]>(['']);
  const createContainerCmdText = ref('');
  const createContainerEntrypointText = ref('');

  const containerStatsMap = ref<Record<string, DockerContainerStats>>({});
  const diagnosticMap = ref<Record<string, DockerContainerDiagnostic>>({});

  let refreshInterval: number | null = null;
  let logsRefreshInterval: number | null = null;
  let statsRefreshInterval: number | null = null;

  const isConnected = computed(() => sshStore.isConnected && sshStore.sessionId);
  const logTailOptions = LOG_TAIL_OPTIONS;

  const runningContainers = computed(() => containers.value.filter((c) => c.state === 'running'));
  const exitedContainers = computed(() => containers.value.filter((c) => c.state === 'exited'));
  const pausedContainers = computed(() => containers.value.filter((c) => c.state === 'paused'));

  const selectedContainerSet = computed(() => new Set(selectedContainerIds.value));
  const selectedContainers = computed(() =>
    containers.value.filter((container) => selectedContainerSet.value.has(container.id))
  );
  const selectedRunningContainers = computed(() =>
    selectedContainers.value.filter((container) => container.state === 'running')
  );
  const selectedStoppedContainers = computed(() =>
    selectedContainers.value.filter((container) => container.state !== 'running')
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
    return filteredContainers.value.every((container) => selectedContainerSet.value.has(container.id));
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
          ''
        ))
        .join('\n');
    }

    const keyword = logsKeyword.value.trim().toLowerCase();
    if (!keyword) {
      return value;
    }

    return value
      .split('\n')
      .filter((line) => line.toLowerCase().includes(keyword))
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

  const refreshContainerDiagnostics = async () => {
    if (!sshStore.sessionId || containers.value.length === 0) {
      diagnosticMap.value = {};
      return;
    }

    try {
      const diagnostics = await dockerApi.getContainerDiagnostics(
        sshStore.sessionId,
        containers.value.map((container) => container.id)
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

  const fetchContainers = async () => {
    if (!sshStore.sessionId) return;
    try {
      containers.value = await dockerApi.listContainers(sshStore.sessionId);
      const visibleIds = new Set(containers.value.map((c) => c.id));
      selectedContainerIds.value = selectedContainerIds.value.filter((id) => visibleIds.has(id));
      await Promise.all([
        refreshContainerDiagnostics(),
        refreshContainerStats(),
      ]);
    } catch {
      toast.error('获取容器列表失败');
    }
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
        newName
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
      .map((item) => item.trim())
      .filter((item) => item.length > 0);
  };

  const toDynamicList = (items: string[]) => {
    return items
      .map((item) => item.trim())
      .filter((item) => item.length > 0);
  };

  const addCreatePort = () => {
    createContainerPorts.value = [...createContainerPorts.value, ''];
  };

  const removeCreatePort = (index: number) => {
    if (createContainerPorts.value.length <= 1) {
      createContainerPorts.value = [''];
      return;
    }
    createContainerPorts.value = createContainerPorts.value.filter((_, i) => i !== index);
  };

  const addCreateEnv = () => {
    createContainerEnvs.value = [...createContainerEnvs.value, ''];
  };

  const removeCreateEnv = (index: number) => {
    if (createContainerEnvs.value.length <= 1) {
      createContainerEnvs.value = [''];
      return;
    }
    createContainerEnvs.value = createContainerEnvs.value.filter((_, i) => i !== index);
  };

  const addCreateVolume = () => {
    createContainerVolumes.value = [...createContainerVolumes.value, ''];
  };

  const removeCreateVolume = (index: number) => {
    if (createContainerVolumes.value.length <= 1) {
      createContainerVolumes.value = [''];
      return;
    }
    createContainerVolumes.value = createContainerVolumes.value.filter((_, i) => i !== index);
  };

  const openCreateContainerDialog = async () => {
    if (sshStore.sessionId && images.value.length === 0) {
      await fetchImages();
    }
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
    createContainerPorts.value = [''];
    createContainerEnvs.value = [''];
    createContainerVolumes.value = [''];
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
        ports: toDynamicList(createContainerPorts.value),
        env: toDynamicList(createContainerEnvs.value),
        volumes: toDynamicList(createContainerVolumes.value),
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
      selectedContainerIds.value = selectedContainerIds.value.filter((item) => item !== id);
      return;
    }
    selectedContainerIds.value = [...selectedContainerIds.value, id];
  };

  const toggleSelectAllVisibleContainers = (event: Event) => {
    const checked = (event.target as HTMLInputElement).checked;
    if (!checked) {
      const visibleIdSet = new Set(filteredContainers.value.map((item) => item.id));
      selectedContainerIds.value = selectedContainerIds.value.filter((id) => !visibleIdSet.has(id));
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
    const ids = selectedStoppedContainers.value.map((container) => container.id);
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
    const ids = selectedRunningContainers.value.map((container) => container.id);
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
        }
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

  return {
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
  };
};

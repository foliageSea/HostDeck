<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useSshStore } from '@/stores/ssh';
import { dockerApi, type DockerContainer, type DockerImage } from '@/api/docker';
import { toast } from 'vue-sonner';
import {
  Play,
  Square,
  RotateCw,
  Trash2,
  FileText,
  Container,
  HardDrive,
  RefreshCw,
  AlertCircle
} from 'lucide-vue-next';
import { Button } from '@/components/ui/button';
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

const sshStore = useSshStore();
const activeTab = ref<'containers' | 'images'>('containers');
const containers = ref<DockerContainer[]>([]);
const images = ref<DockerImage[]>([]);
const loading = ref(false);
const dockerAvailable = ref<boolean | null>(null);
const refreshing = ref(false);

// Logs dialog
const logsDialogOpen = ref(false);
const logsContainer = ref<DockerContainer | null>(null);
const logsContent = ref('');
const logsLoading = ref(false);

// Confirm dialog
const confirmDialogOpen = ref(false);
const confirmAction = ref<'removeContainer' | 'removeImage' | null>(null);
const confirmItem = ref<DockerContainer | DockerImage | null>(null);
const confirmForce = ref(false);

let refreshInterval: NodeJS.Timeout | null = null;

const isConnected = computed(() => sshStore.isConnected && sshStore.sessionId);

const runningContainers = computed(() =>
  containers.value.filter(c => c.state === 'running')
);

const stoppedContainers = computed(() =>
  containers.value.filter(c => c.state !== 'running')
);

const checkDocker = async () => {
  if (!sshStore.sessionId) return;
  try {
    const result = await dockerApi.checkDocker(sshStore.sessionId);
    dockerAvailable.value = result.available;
  } catch (e) {
    dockerAvailable.value = false;
  }
};

const fetchContainers = async () => {
  if (!sshStore.sessionId) return;
  try {
    containers.value = await dockerApi.listContainers(sshStore.sessionId);
  } catch (e) {
    toast.error('获取容器列表失败');
  }
};

const fetchImages = async () => {
  if (!sshStore.sessionId) return;
  try {
    images.value = await dockerApi.listImages(sshStore.sessionId);
  } catch (e) {
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
  } catch (e) {
    toast.error('启动容器失败');
  }
};

const stopContainer = async (container: DockerContainer) => {
  if (!sshStore.sessionId) return;
  try {
    await dockerApi.stopContainer(sshStore.sessionId, container.id);
    toast.success(`容器 ${container.name} 已停止`);
    await fetchContainers();
  } catch (e) {
    toast.error('停止容器失败');
  }
};

const restartContainer = async (container: DockerContainer) => {
  if (!sshStore.sessionId) return;
  try {
    await dockerApi.restartContainer(sshStore.sessionId, container.id);
    toast.success(`容器 ${container.name} 已重启`);
    await fetchContainers();
  } catch (e) {
    toast.error('重启容器失败');
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

const confirmRemove = async () => {
  if (!sshStore.sessionId || !confirmItem.value) return;

  try {
    if (confirmAction.value === 'removeContainer') {
      await dockerApi.removeContainer(sshStore.sessionId, confirmItem.value.id, confirmForce.value);
      toast.success('容器已删除');
      await fetchContainers();
    } else if (confirmAction.value === 'removeImage') {
      await dockerApi.removeImage(sshStore.sessionId, confirmItem.value.id, confirmForce.value);
      toast.success('镜像已删除');
      await fetchImages();
    }
  } catch (e) {
    toast.error('删除失败');
  }

  confirmDialogOpen.value = false;
  confirmItem.value = null;
};

const viewLogs = async (container: DockerContainer) => {
  if (!sshStore.sessionId) return;
  logsContainer.value = container;
  logsDialogOpen.value = true;
  logsLoading.value = true;

  try {
    const result = await dockerApi.getContainerLogs(sshStore.sessionId, container.id, 200);
    logsContent.value = result.logs;
  } catch (e) {
    toast.error('获取日志失败');
    logsContent.value = '';
  } finally {
    logsLoading.value = false;
  }
};

const formatDate = (dateStr?: string) => {
  if (!dateStr) return '-';
  const date = new Date(dateStr);
  return date.toLocaleString('zh-CN');
};

const shortId = (id: string) => {
  return id.substring(0, 12);
};

const copyToClipboard = async (text: string) => {
  try {
    await navigator.clipboard.writeText(text);
    toast.success('已复制到剪贴板');
  } catch (e) {
    toast.error('复制失败');
  }
};

const parsePort = (portStr: string) => {
  // 匹配格式: 0.0.0.0:8080->80/tcp 或 :::8080->80/tcp
  const match = portStr.match(/^(.*):(\d+)->(\d+)\/(tcp|udp)$/);
  if (match) {
    return {
      host: match[1],
      hostPort: match[2],
      containerPort: match[3],
      protocol: match[4],
      raw: portStr
    };
  }
  return { raw: portStr };
};

const getPortDisplay = (portStr: string) => {
  const parsed = parsePort(portStr);
  if (parsed.hostPort && parsed.containerPort) {
    return `${parsed.hostPort}:${parsed.containerPort}`;
  }
  return portStr;
};

onMounted(async () => {
  if (isConnected.value) {
    loading.value = true;
    await checkDocker();
    if (dockerAvailable.value) {
      await fetchContainers();
    }
    loading.value = false;

    // Auto refresh every 10 seconds
    refreshInterval = setInterval(() => {
      if (activeTab.value === 'containers' && !logsDialogOpen.value && !confirmDialogOpen.value) {
        fetchContainers();
      }
    }, 10000);
  }
});

onUnmounted(() => {
  if (refreshInterval) {
    clearInterval(refreshInterval);
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
    dockerAvailable.value = null;
  }
});
</script>

<template>
  <div class="h-full flex flex-col bg-background">
    <!-- Header -->
    <div class="flex items-center justify-between px-4 py-3 border-b">
      <div class="flex items-center gap-4">
        <h2 class="text-lg font-semibold">Docker 管理</h2>
        <div class="flex bg-muted rounded-lg p-1">
          <button
            class="px-3 py-1 text-sm rounded-md transition-colors"
            :class="activeTab === 'containers' ? 'bg-background shadow-sm' : 'text-muted-foreground hover:text-foreground'"
            @click="activeTab = 'containers'"
          >
            <div class="flex items-center gap-2">
              <Container class="w-4 h-4" />
              容器
              <span v-if="containers.length > 0" class="inline-flex items-center rounded-md bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-800">
                {{ containers.length }}
              </span>
            </div>
          </button>
          <button
            class="px-3 py-1 text-sm rounded-md transition-colors"
            :class="activeTab === 'images' ? 'bg-background shadow-sm' : 'text-muted-foreground hover:text-foreground'"
            @click="activeTab = 'images'"
          >
            <div class="flex items-center gap-2">
              <HardDrive class="w-4 h-4" />
              镜像
              <span v-if="images.length > 0" class="inline-flex items-center rounded-md bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-800">
                {{ images.length }}
              </span>
            </div>
          </button>
        </div>
      </div>
      <Button
        variant="outline"
        size="sm"
        :disabled="refreshing || !dockerAvailable"
        @click="refresh"
      >
        <RefreshCw class="w-4 h-4 mr-2" :class="{ 'animate-spin': refreshing }" />
        刷新
      </Button>
    </div>

    <!-- Content -->
    <div class="flex-1 overflow-auto custom-scrollbar p-4">
      <!-- Not connected -->
      <div v-if="!isConnected" class="h-full flex flex-col items-center justify-center text-muted-foreground">
        <AlertCircle class="w-12 h-12 mb-4 opacity-50" />
        <p>请先连接 SSH 服务器</p>
      </div>

      <!-- Docker not available -->
      <div v-else-if="dockerAvailable === false" class="h-full flex flex-col items-center justify-center text-muted-foreground">
        <AlertCircle class="w-12 h-12 mb-4 opacity-50" />
        <p>该服务器未安装 Docker 或无法访问</p>
      </div>

      <!-- Loading -->
      <div v-else-if="loading" class="space-y-4">
        <Skeleton v-for="i in 5" :key="i" class="h-12 w-full" />
      </div>

      <!-- Containers Tab -->
      <div v-else-if="activeTab === 'containers'" class="space-y-4">
        <!-- Stats -->
        <div class="grid grid-cols-3 gap-4">
          <div class="bg-muted/50 rounded-lg p-4">
            <div class="text-sm text-muted-foreground">总容器数</div>
            <div class="text-2xl font-bold">{{ containers.length }}</div>
          </div>
          <div class="bg-muted/50 rounded-lg p-4">
            <div class="text-sm text-muted-foreground">运行中</div>
            <div class="text-2xl font-bold text-green-600">{{ runningContainers.length }}</div>
          </div>
          <div class="bg-muted/50 rounded-lg p-4">
            <div class="text-sm text-muted-foreground">已停止</div>
            <div class="text-2xl font-bold text-gray-500">{{ stoppedContainers.length }}</div>
          </div>
        </div>

        <!-- Containers Table -->
        <div class="border rounded-lg overflow-hidden">
          <div class="max-h-[calc(100vh-280px)] overflow-auto custom-scrollbar">
            <Table>
              <TableHeader class="sticky top-0 bg-background z-10">
                <TableRow class="bg-muted/50">
                  <TableHead class="w-24">ID</TableHead>
                  <TableHead>名称</TableHead>
                  <TableHead>镜像</TableHead>
                  <TableHead>状态</TableHead>
                  <TableHead class="w-32">端口</TableHead>
                  <TableHead class="w-32">创建时间</TableHead>
                  <TableHead class="w-40 text-right">操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
              <TableRow v-if="containers.length === 0">
                <TableCell colspan="7" class="text-center text-muted-foreground py-8">
                  暂无容器
                </TableCell>
              </TableRow>
              <TableRow v-for="container in containers" :key="container.id">
                <TableCell class="font-mono text-xs">{{ shortId(container.id) }}</TableCell>
                <TableCell class="font-medium">{{ container.name }}</TableCell>
                <TableCell class="text-muted-foreground">{{ container.image }}</TableCell>
                <TableCell>
                  <span
                    class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"
                    :class="{
                      'bg-green-100 text-green-800': container.state === 'running',
                      'bg-gray-100 text-gray-800': container.state === 'exited',
                      'bg-yellow-100 text-yellow-800': container.state === 'paused',
                      'bg-red-100 text-red-800': !['running', 'exited', 'paused'].includes(container.state)
                    }"
                  >
                    {{ container.state }}
                  </span>
                </TableCell>
                <TableCell class="text-xs">
                  <TooltipProvider v-if="container.ports.length">
                    <Tooltip>
                      <TooltipTrigger as-child>
                        <div class="flex flex-wrap gap-1 cursor-pointer">
                          <span
                            v-for="port in container.ports.slice(0, 3)"
                            :key="port"
                            class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-blue-50 text-blue-700 border border-blue-200 dark:bg-blue-900/30 dark:text-blue-300 dark:border-blue-800"
                          >
                            {{ getPortDisplay(port) }}
                          </span>
                          <span
                            v-if="container.ports.length > 3"
                            class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-400"
                          >
                            +{{ container.ports.length - 3 }}
                          </span>
                        </div>
                      </TooltipTrigger>
                      <TooltipContent class="max-w-xs">
                        <div class="space-y-2">
                          <div class="text-xs font-semibold">端口映射</div>
                          <div class="space-y-1">
                            <div
                              v-for="port in container.ports"
                              :key="port"
                              class="flex items-center justify-between gap-3 text-xs group cursor-pointer hover:bg-primary-foreground/10 rounded px-1 -mx-1 py-0.5 transition-colors"
                              @click="copyToClipboard(port)"
                            >
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
                <TableCell class="text-xs text-muted-foreground">
                  {{ formatDate(container.createdAt) }}
                </TableCell>
                <TableCell class="text-right">
                  <div class="flex items-center justify-end gap-1">
                    <Button
                      v-if="container.state !== 'running'"
                      variant="ghost"
                      size="icon"
                      class="h-8 w-8"
                      @click="startContainer(container)"
                    >
                      <Play class="w-4 h-4 text-green-600" />
                    </Button>
                    <Button
                      v-if="container.state === 'running'"
                      variant="ghost"
                      size="icon"
                      class="h-8 w-8"
                      @click="stopContainer(container)"
                    >
                      <Square class="w-4 h-4 text-amber-600" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      class="h-8 w-8"
                      @click="restartContainer(container)"
                    >
                      <RotateCw class="w-4 h-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      class="h-8 w-8"
                      @click="viewLogs(container)"
                    >
                      <FileText class="w-4 h-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      class="h-8 w-8"
                      @click="showRemoveContainerConfirm(container)"
                    >
                      <Trash2 class="w-4 h-4 text-red-600" />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            </TableBody>
          </Table>
          </div>
        </div>
      </div>

      <!-- Images Tab -->
      <div v-else-if="activeTab === 'images'" class="space-y-4">
        <!-- Images Table -->
        <div class="border rounded-lg overflow-hidden">
          <div class="max-h-[calc(100vh-240px)] overflow-auto custom-scrollbar">
            <Table>
              <TableHeader class="sticky top-0 bg-background z-10">
                <TableRow class="bg-muted/50">
                  <TableHead class="w-24">ID</TableHead>
                  <TableHead>仓库</TableHead>
                  <TableHead>标签</TableHead>
                  <TableHead>大小</TableHead>
                  <TableHead class="w-32">创建时间</TableHead>
                  <TableHead class="w-20 text-right">操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
              <TableRow v-if="images.length === 0">
                <TableCell colspan="6" class="text-center text-muted-foreground py-8">
                  暂无镜像
                </TableCell>
              </TableRow>
              <TableRow v-for="image in images" :key="image.id">
                <TableCell class="font-mono text-xs">{{ shortId(image.id) }}</TableCell>
                <TableCell class="font-medium">{{ image.repository }}</TableCell>
                <TableCell>
                  <span class="inline-flex items-center rounded-md border px-2 py-0.5 text-xs font-medium">
                    {{ image.tag }}
                  </span>
                </TableCell>
                <TableCell class="text-muted-foreground">{{ image.size }}</TableCell>
                <TableCell class="text-xs text-muted-foreground">
                  {{ formatDate(image.createdAt) }}
                </TableCell>
                <TableCell class="text-right">
                  <Button
                    variant="ghost"
                    size="icon"
                    class="h-8 w-8"
                    @click="showRemoveImageConfirm(image)"
                  >
                    <Trash2 class="w-4 h-4 text-red-600" />
                  </Button>
                </TableCell>
              </TableRow>
            </TableBody>
          </Table>
          </div>
        </div>
      </div>
    </div>

    <!-- Logs Dialog -->
    <Dialog v-model:open="logsDialogOpen">
      <DialogContent class="max-w-4xl max-h-[80vh] flex flex-col">
        <DialogHeader>
          <DialogTitle class="flex items-center gap-2">
            <FileText class="w-5 h-5" />
            容器日志: {{ logsContainer?.name }}
          </DialogTitle>
          <DialogDescription>
            显示最近 200 行日志
          </DialogDescription>
        </DialogHeader>
        <div class="flex-1 bg-black rounded-md p-4 min-h-[400px] overflow-auto custom-scrollbar">
          <div v-if="logsLoading" class="space-y-2">
            <Skeleton v-for="i in 10" :key="i" class="h-4 w-full" />
          </div>
          <pre v-else class="text-sm text-gray-300 font-mono whitespace-pre-wrap break-all">{{ logsContent || '暂无日志' }}</pre>
        </div>
      </DialogContent>
    </Dialog>

    <!-- Confirm Dialog -->
    <AlertDialog v-model:open="confirmDialogOpen">
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>确认删除</AlertDialogTitle>
          <AlertDialogDescription>
            <span v-if="confirmAction === 'removeContainer'">
              确定要删除容器 <strong>{{ (confirmItem as DockerContainer)?.name }}</strong> 吗？
              <span v-if="confirmForce" class="block mt-2 text-red-500">
                警告：该容器正在运行，强制删除可能导致数据丢失。
              </span>
            </span>
            <span v-else>
              确定要删除镜像 <strong>{{ (confirmItem as DockerImage)?.repository }}:{{ (confirmItem as DockerImage)?.tag }}</strong> 吗？
            </span>
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>取消</AlertDialogCancel>
          <AlertDialogAction class="bg-red-600 hover:bg-red-700" @click="confirmRemove">
            删除
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </div>
</template>

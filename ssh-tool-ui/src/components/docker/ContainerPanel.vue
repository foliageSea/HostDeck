<script setup lang="ts">
import type { DockerContainer } from '@/api/docker';
import {
  Play,
  Square,
  RotateCw,
  Trash2,
  FileText,
  Terminal,
  RefreshCw,
  Info,
  Pause,
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
  TableRow,
} from '@/components/ui/table';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';

defineProps<{
  containers: DockerContainer[];
  runningContainers: DockerContainer[];
  exitedContainers: DockerContainer[];
  pausedContainers: DockerContainer[];
  containerNameQuery: string;
  containerImageQuery: string;
  containerStateFilter: 'all' | 'running' | 'exited' | 'paused';
  containerSortBy: 'createdAt' | 'name' | 'image';
  containerSortOrder: 'asc' | 'desc';
  setContainerNameQuery: (value: string) => void;
  setContainerImageQuery: (value: string) => void;
  setContainerStateFilter: (value: 'all' | 'running' | 'exited' | 'paused') => void;
  setContainerSortBy: (value: 'createdAt' | 'name' | 'image') => void;
  setContainerSortOrder: (value: 'asc' | 'desc') => void;
  selectedContainerIds: string[];
  selectedStoppedContainers: DockerContainer[];
  selectedRunningContainers: DockerContainer[];
  batchProcessing: boolean;
  allVisibleContainersSelected: boolean;
  filteredContainers: DockerContainer[];
  selectedContainerSet: Set<string>;
  recreateLoadingId: string | null;
  getPortDisplay: (port: string) => string;
  getContainerStats: (id: string) => { cpuPercent?: string; memPercent?: string } | undefined;
  formatDate: (date?: string) => string;
  shortId: (id: string) => string;
  isUnhealthyContainer: (id: string) => boolean;
  isFrequentRestart: (id: string) => boolean;
  isExitedAbnormally: (container: DockerContainer) => boolean;
  copyToClipboard: (text: string) => Promise<void>;
  clearSelectedContainers: () => void;
  batchStartSelected: () => Promise<void>;
  batchStopSelected: () => Promise<void>;
  showRemoveStoppedContainersConfirm: () => void;
  toggleSelectAllVisibleContainers: (event: Event) => void;
  toggleContainerSelection: (id: string) => void;
  openContainerDetail: (container: DockerContainer) => Promise<void>;
  startContainer: (container: DockerContainer) => Promise<void>;
  stopContainer: (container: DockerContainer) => Promise<void>;
  restartContainer: (container: DockerContainer) => Promise<void>;
  pauseContainer: (container: DockerContainer) => Promise<void>;
  unpauseContainer: (container: DockerContainer) => Promise<void>;
  viewLogs: (container: DockerContainer) => Promise<void>;
  openRenameDialog: (container: DockerContainer) => void;
  recreateContainer: (container: DockerContainer) => Promise<void>;
  enterShell: (container: DockerContainer) => Promise<void>;
  showRemoveContainerConfirm: (container: DockerContainer) => void;
}>();
</script>

<template>
  <div class="space-y-4">
    <div class="grid grid-cols-4 gap-4">
      <button class="bg-muted/50 rounded-lg p-4 text-left transition-colors hover:bg-muted"
        :class="containerStateFilter === 'all' ? 'ring-1 ring-primary' : ''"
        @click="setContainerStateFilter('all')">
        <div class="text-sm text-muted-foreground">总容器数</div>
        <div class="text-2xl font-bold">{{ containers.length }}</div>
      </button>
      <button class="bg-muted/50 rounded-lg p-4 text-left transition-colors hover:bg-muted"
        :class="containerStateFilter === 'running' ? 'ring-1 ring-primary' : ''"
        @click="setContainerStateFilter('running')">
        <div class="text-sm text-muted-foreground">运行中</div>
        <div class="text-2xl font-bold text-green-600">{{ runningContainers.length }}</div>
      </button>
      <button class="bg-muted/50 rounded-lg p-4 text-left transition-colors hover:bg-muted"
        :class="containerStateFilter === 'exited' ? 'ring-1 ring-primary' : ''"
        @click="setContainerStateFilter('exited')">
        <div class="text-sm text-muted-foreground">已停止</div>
        <div class="text-2xl font-bold text-gray-500">{{ exitedContainers.length }}</div>
      </button>
      <button class="bg-muted/50 rounded-lg p-4 text-left transition-colors hover:bg-muted"
        :class="containerStateFilter === 'paused' ? 'ring-1 ring-primary' : ''"
        @click="setContainerStateFilter('paused')">
        <div class="text-sm text-muted-foreground">已暂停</div>
        <div class="text-2xl font-bold text-yellow-600">{{ pausedContainers.length }}</div>
      </button>
    </div>

    <div class="border rounded-lg p-3 bg-muted/20 space-y-3">
      <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-6 gap-3">
        <Input :model-value="containerNameQuery" @update:model-value="(value) => setContainerNameQuery(String(value))" placeholder="搜索容器名称"/>
        <Input :model-value="containerImageQuery" @update:model-value="(value) => setContainerImageQuery(String(value))" placeholder="搜索镜像名称"/>

        <select :value="containerStateFilter" @change="setContainerStateFilter(($event.target as HTMLSelectElement).value as 'all' | 'running' | 'exited' | 'paused')"
          class="h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring">
          <option value="all">状态：全部</option>
          <option value="running">状态：running</option>
          <option value="exited">状态：exited</option>
          <option value="paused">状态：paused</option>
        </select>

        <select :value="containerSortBy" @change="setContainerSortBy(($event.target as HTMLSelectElement).value as 'createdAt' | 'name' | 'image')"
          class="h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring">
          <option value="createdAt">排序：创建时间</option>
          <option value="name">排序：名称</option>
          <option value="image">排序：镜像</option>
        </select>

        <select :value="containerSortOrder" @change="setContainerSortOrder(($event.target as HTMLSelectElement).value as 'asc' | 'desc')"
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
</template>

<script setup lang="ts">
import type { DockerImage } from '@/api/docker';
import { Trash2, Info, Container, Tag } from 'lucide-vue-next';
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

defineProps<{
  imageQuery: string;
  imageUsageFilter: 'all' | 'dangling' | 'unused';
  imageSortBy: 'createdAt' | 'repository' | 'tag' | 'size';
  imageSortOrder: 'asc' | 'desc';
  setImageQuery: (value: string) => void;
  setImageUsageFilter: (value: 'all' | 'dangling' | 'unused') => void;
  setImageSortBy: (value: 'createdAt' | 'repository' | 'tag' | 'size') => void;
  setImageSortOrder: (value: 'asc' | 'desc') => void;
  filteredImages: DockerImage[];
  shortId: (id: string) => string;
  formatDate: (date?: string) => string;
  showPruneDanglingConfirm: () => void;
  showPruneUnusedConfirm: () => void;
  viewImageHistory: (image: DockerImage) => Promise<void>;
  viewImageRefs: (image: DockerImage) => Promise<void>;
  openImageTagDialog: (image: DockerImage) => void;
  showRemoveImageConfirm: (image: DockerImage) => void;
}>();
</script>

<template>
  <div class="space-y-4">
    <div class="border rounded-lg p-3 bg-muted/20 space-y-3">
      <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-6 gap-3">
        <Input :model-value="imageQuery" @update:model-value="(value) => setImageQuery(String(value))" placeholder="搜索仓库或标签"/>

        <select :value="imageUsageFilter" @change="setImageUsageFilter(($event.target as HTMLSelectElement).value as 'all' | 'dangling' | 'unused')"
          class="h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring">
          <option value="all">镜像类型：全部</option>
          <option value="dangling">仅 dangling 镜像</option>
          <option value="unused">仅无引用镜像</option>
        </select>

        <select :value="imageSortBy" @change="setImageSortBy(($event.target as HTMLSelectElement).value as 'createdAt' | 'repository' | 'tag' | 'size')"
          class="h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring">
          <option value="createdAt">排序：创建时间</option>
          <option value="repository">排序：仓库</option>
          <option value="tag">排序：标签</option>
          <option value="size">排序：大小</option>
        </select>

        <select :value="imageSortOrder" @change="setImageSortOrder(($event.target as HTMLSelectElement).value as 'asc' | 'desc')"
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
</template>

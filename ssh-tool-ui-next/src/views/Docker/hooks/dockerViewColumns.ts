import type { DataTableColumns } from 'naive-ui'

import type { DockerImageContainerRef, DockerImageHistoryItem } from '@/api/docker'

export const imageHistoryColumns: DataTableColumns<DockerImageHistoryItem> = [
  { title: 'ID', key: 'id', width: 180 },
  { title: '时间', key: 'createdSince', width: 140 },
  { title: '大小', key: 'size', width: 120 },
  { title: '命令', key: 'createdBy', width: 560 },
  { title: '备注', key: 'comment', width: 260 },
]

export const imageRefsColumns: DataTableColumns<DockerImageContainerRef> = [
  { title: '容器名', key: 'name' },
  { title: '镜像', key: 'image' },
  { title: '状态', key: 'status' },
  { title: 'State', key: 'state' },
]

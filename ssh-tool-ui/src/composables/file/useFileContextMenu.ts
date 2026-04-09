import { ref, computed } from 'vue'
import { toast } from 'vue-sonner'
import type { FileItem } from '@/stores/file'
import type { MenuItem } from '@/components/file/FileContextMenu.vue'
import {
  FolderIcon, FolderPlusIcon, DownloadIcon,
  CopyIcon, ScissorsIcon, ClipboardPasteIcon,
  EditIcon, Trash2Icon, TypeIcon, RefreshCwIcon,
  ClipboardIcon, StarIcon, Terminal as TerminalIcon, FilePlusIcon, InfoIcon
} from 'lucide-vue-next'

/**
 * 封装文件管理器的右键菜单逻辑
 */
export function useFileContextMenu(fileStore: any, operations: any) {
  const contextMenu = ref({ visible: false, x: 0, y: 0, file: null as FileItem | null })

  const handleContextMenu = (e: MouseEvent, file: FileItem) => {
    if (!fileStore.selectedFiles.has(file.filename)) {
      fileStore.toggleSelection(file.filename, false)
    }

    contextMenu.value = {
      visible: true,
      x: e.clientX,
      y: e.clientY,
      file
    }
  }

  const handleContainerContextMenu = (e: MouseEvent) => {
    fileStore.clearSelection()
    contextMenu.value = {
      visible: true,
      x: e.clientX,
      y: e.clientY,
      file: null
    }
  }

  const closeContextMenu = () => {
    contextMenu.value.visible = false
  }

  const handleCopyPath = async () => {
    const paths = Array.from(fileStore.selectedFiles).map(filename => operations.getFullPath(filename as string))
    if (paths.length === 0) return

    try {
      await navigator.clipboard.writeText(paths.join('\n'))
      toast.success('已复制路径')
      closeContextMenu()
    } catch (e) {
      console.error(e)
      toast.error('复制失败')
    }
  }

  const contextMenuItems = computed<MenuItem[]>(() => {
    const items: MenuItem[] = []
    const singleSelection = fileStore.selectedFiles.size === 1
    const hasSelection = fileStore.selectedFiles.size > 0

    if (!hasSelection) {
      items.push({
        label: '新建文件',
        icon: FilePlusIcon as any,
        action: operations.openCreateFileModal
      })
      items.push({
        label: '新建文件夹',
        icon: FolderPlusIcon as any,
        action: operations.openMkdirModal
      })
      items.push({ separator: true, label: '' })
    }

    if (singleSelection) {
      const file = fileStore.files.find((f: FileItem) => f.filename === Array.from(fileStore.selectedFiles)[0])
      if (file) {
        items.push({
          label: '打开',
          icon: (file.isDirectory ? FolderIcon : EditIcon) as any,
          action: () => operations.handleOpen(file)
        })

        if (file.isDirectory) {
          const fullPath = operations.getFullPath(file.filename)
          const isFav = fileStore.isFavorite(fullPath)
          items.push({
            label: isFav ? '取消收藏' : '收藏目录',
            icon: StarIcon as any,
            action: () => fileStore.toggleFavorite(fullPath)
          })
        }

        items.push({
          label: '属性',
          icon: InfoIcon as any,
          action: operations.openPropertiesModal
        })
      }
    }

    if (hasSelection) {
      items.push({
        label: '下载',
        icon: DownloadIcon as any,
        action: operations.handleDownload
      })
      items.push({
        label: '复制路径',
        icon: ClipboardIcon as any,
        action: handleCopyPath
      })
      items.push({ separator: true, label: '' })
      items.push({
        label: '复制',
        icon: CopyIcon as any,
        action: () => fileStore.copySelection()
      })
      items.push({
        label: '剪切',
        icon: ScissorsIcon as any,
        action: () => fileStore.cutSelection()
      })
    }

    if (!hasSelection) {
      items.push({
        label: '在终端中打开',
        icon: TerminalIcon as any,
        action: operations.openTerminalHere
      })
      items.push({ separator: true, label: '' })
    }

    if (fileStore.clipboard) {
      items.push({
        label: '粘贴',
        icon: ClipboardPasteIcon as any,
        action: operations.handlePaste
      })
    }

    if (hasSelection) {
      items.push({ separator: true, label: '' })
      if (singleSelection) {
        items.push({
          label: '重命名',
          icon: TypeIcon as any,
          action: operations.openRenameModal
        })
      }
      items.push({
        label: '删除',
        icon: Trash2Icon as any,
        action: operations.openDeleteModal
      })
    }

    items.push({ separator: true, label: '' })
    items.push({
      label: '刷新',
      icon: RefreshCwIcon as any,
      action: fileStore.refresh
    })

    return items
  })

  return {
    contextMenu,
    handleContextMenu,
    handleContainerContextMenu,
    closeContextMenu,
    contextMenuItems
  }
}

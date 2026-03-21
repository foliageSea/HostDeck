import { ref, reactive } from 'vue'
import { useEventListener } from '@vueuse/core'

/**
 * 封装文件管理器的框选逻辑
 * @param fileStore 文件 Store 实例
 */
export function useFileSelection(fileStore: any) {
  const containerRef = ref<HTMLElement | null>(null)
  const isSelecting = ref(false)
  
  const selectionBox = reactive({
    visible: false,
    x: 0,
    y: 0,
    width: 0,
    height: 0,
    startX: 0,
    startY: 0,
    startClientX: 0,
    startClientY: 0
  })

  let fileRects: { filename: string; rect: DOMRect }[] = []
  let initialSelection = new Set<string>()

  /**
   * 处理鼠标按下事件，开始框选
   */
  const handleMouseDown = (e: MouseEvent) => {
    // 仅处理左键点击
    if (e.button !== 0) return

    // 如果点击在文件项内部，则忽略框选
    if ((e.target as Element).closest('[data-filename]')) return

    isSelecting.value = true
    const container = containerRef.value
    if (!container) return

    const rect = container.getBoundingClientRect()
    selectionBox.startX = e.clientX - rect.left
    selectionBox.startY = e.clientY - rect.top
    selectionBox.startClientX = e.clientX
    selectionBox.startClientY = e.clientY

    selectionBox.x = selectionBox.startX
    selectionBox.y = selectionBox.startY
    selectionBox.width = 0
    selectionBox.height = 0
    selectionBox.visible = true

    // 缓存所有文件的边界信息，优化性能
    const elements = container.querySelectorAll('[data-filename]')
    fileRects = Array.from(elements).map(el => ({
      filename: el.getAttribute('data-filename') || '',
      rect: el.getBoundingClientRect()
    }))

    // 处理组合键
    if (e.ctrlKey || e.metaKey) {
      initialSelection = new Set(fileStore.selectedFiles)
    } else {
      initialSelection = new Set()
      fileStore.clearSelection()
    }
  }

  /**
   * 处理鼠标移动事件，更新选框并计算碰撞
   */
  const handleMouseMove = (e: MouseEvent) => {
    if (!isSelecting.value || !containerRef.value) return

    const containerRect = containerRef.value.getBoundingClientRect()

    // 限制在容器范围内
    const currentX = Math.max(0, Math.min(e.clientX - containerRect.left, containerRect.width))
    const currentY = Math.max(0, Math.min(e.clientY - containerRect.top, containerRect.height))

    const x = Math.min(selectionBox.startX, currentX)
    const y = Math.min(selectionBox.startY, currentY)
    const width = Math.abs(currentX - selectionBox.startX)
    const height = Math.abs(currentY - selectionBox.startY)

    selectionBox.x = x
    selectionBox.y = y
    selectionBox.width = width
    selectionBox.height = height

    // 在视口坐标系下计算交叉
    const boxLeft = containerRect.left + x
    const boxTop = containerRect.top + y
    const boxRight = boxLeft + width
    const boxBottom = boxTop + height

    const newSelection = new Set(initialSelection)

    fileRects.forEach(({ filename, rect }) => {
      const isIntersecting = !(
        rect.right < boxLeft ||
        rect.left > boxRight ||
        rect.bottom < boxTop ||
        rect.top > boxBottom
      )

      if (isIntersecting) {
        newSelection.add(filename)
      }
    })

    fileStore.selectedFiles = newSelection
  }

  /**
   * 处理鼠标抬起事件，结束框选
   */
  const handleMouseUp = () => {
    if (!isSelecting.value) return
    isSelecting.value = false
    selectionBox.visible = false
    fileRects = []
    initialSelection.clear()
  }

  useEventListener(window, 'mousemove', handleMouseMove)
  useEventListener(window, 'mouseup', handleMouseUp)

  return {
    containerRef,
    selectionBox,
    handleMouseDown
  }
}

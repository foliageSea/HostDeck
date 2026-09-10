import { computed, nextTick, ref, type CSSProperties, type ShallowRef } from 'vue'
import type { Terminal } from '@xterm/xterm'
import { terminalApi, type TerminalSnippet } from '@/api/terminal'
import {
  buildTerminalCompletions,
  TerminalInputModel,
  type TerminalCompletionItem,
} from '../completion/terminalCompletion'

interface UseTerminalCompletionOptions {
  sendInput: (data: string) => boolean
  terminal: ShallowRef<Terminal | null>
}

const POPOVER_WIDTH = 380
const POPOVER_ESTIMATED_HEIGHT = 270
const VIEWPORT_MARGIN = 12

export function useTerminalCompletion({ sendInput, terminal }: UseTerminalCompletionOptions) {
  const inputModel = new TerminalInputModel()
  const snippets = ref<TerminalSnippet[]>([])
  const items = ref<TerminalCompletionItem[]>([])
  const activeIndex = ref(0)
  const anchorStyle = ref<CSSProperties>({ left: '0px', top: '0px' })
  let snippetRequestId = 0
  let outputTail = ''

  const visible = computed(() => items.value.length > 0)

  function close() {
    items.value = []
    activeIndex.value = 0
  }

  function isNormalBuffer() {
    return terminal.value?.buffer.active.type !== 'alternate'
  }

  function updateAnchor() {
    const textarea = terminal.value?.textarea
    if (!textarea) {
      return
    }

    const rect = textarea.getBoundingClientRect()
    const maxLeft = Math.max(VIEWPORT_MARGIN, window.innerWidth - POPOVER_WIDTH - VIEWPORT_MARGIN)
    const left = Math.min(Math.max(rect.left, VIEWPORT_MARGIN), maxLeft)
    const shouldOpenAbove = rect.bottom + POPOVER_ESTIMATED_HEIGHT > window.innerHeight
    const top = shouldOpenAbove
      ? Math.max(VIEWPORT_MARGIN, rect.top - POPOVER_ESTIMATED_HEIGHT - 8)
      : Math.min(rect.bottom + 8, window.innerHeight - VIEWPORT_MARGIN)

    anchorStyle.value = { left: `${left}px`, top: `${top}px` }
  }

  function updateItems() {
    if (!inputModel.reliable || !isNormalBuffer()) {
      close()
      return
    }

    items.value = buildTerminalCompletions(inputModel.line, snippets.value, inputModel.history)
    activeIndex.value = Math.min(activeIndex.value, Math.max(0, items.value.length - 1))
    if (items.value.length > 0) {
      void nextTick(updateAnchor)
    }
  }

  function handleData(data: string) {
    inputModel.handleData(data)
    updateItems()
  }

  function moveActive(delta: number) {
    if (!items.value.length) {
      return
    }
    activeIndex.value = (activeIndex.value + delta + items.value.length) % items.value.length
  }

  function accept(item = items.value[activeIndex.value], execute = false) {
    if (!item || !inputModel.reliable || !item.command.startsWith(inputModel.line)) {
      close()
      return false
    }

    const suffix = item.command.slice(inputModel.line.length)
    if (suffix && !sendInput(suffix)) {
      close()
      return false
    }
    if (execute && !sendInput('\r')) {
      close()
      return false
    }
    close()
    terminal.value?.focus()
    return true
  }

  function handleKeyEvent(event: KeyboardEvent) {
    if (event.type !== 'keydown' || !visible.value) {
      return false
    }

    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      moveActive(event.key === 'ArrowDown' ? 1 : -1)
    } else if (event.key === 'Tab') {
      accept()
    } else if (event.key === 'Enter') {
      accept(undefined, true)
    } else if (event.key === 'Escape') {
      close()
    } else {
      return false
    }

    event.preventDefault()
    event.stopPropagation()
    return true
  }

  function handleOutput(data: string) {
    const plainText = data.replace(/\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))/g, '')
    outputTail = `${outputTail}${plainText}`.slice(-200)
    if (/(?:password|passphrase|token|密码)\s*[:：]?\s*$/i.test(outputTail)) {
      inputModel.suspendLine()
      close()
    }
  }

  async function refreshSnippets() {
    const requestId = ++snippetRequestId
    try {
      const response = await terminalApi.listSnippets()
      if (requestId !== snippetRequestId) {
        return
      }
      snippets.value = response
      updateItems()
    } catch (error) {
      console.warn('Failed to load terminal completion snippets', error)
    }
  }

  function reset() {
    inputModel.resetLine()
    close()
  }

  return {
    accept,
    activeIndex,
    anchorStyle,
    close,
    handleData,
    handleKeyEvent,
    handleOutput,
    items,
    refreshSnippets,
    reset,
    updateAnchor,
    visible,
  }
}

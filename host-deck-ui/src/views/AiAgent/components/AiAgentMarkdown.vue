<script lang="ts">
import DOMPurify from 'dompurify'
import { marked } from 'marked'

// Register once per module, rather than adding another global hook for every message.
DOMPurify.addHook('afterSanitizeAttributes', (node) => {
  if (node.tagName === 'A') {
    node.setAttribute('target', '_blank')
    node.setAttribute('rel', 'noopener noreferrer nofollow')
  }
})

marked.setOptions({ breaks: true, gfm: true })
</script>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { highlightCode } from '@/lib/code-highlight'
import { getUiApi } from '@/lib/ui'

const props = defineProps<{
  content: string
  streaming?: boolean
}>()

const emit = defineEmits<{ rendered: [] }>()
const markdownElement = ref<HTMLElement>()
const displayedContent = ref(props.content)
let renderTimer: ReturnType<typeof setTimeout> | undefined

function cancelScheduledRender() {
  if (renderTimer === undefined) return
  clearTimeout(renderTimer)
  renderTimer = undefined
}

watch(
  () => [props.content, props.streaming] as const,
  () => {
    if (!props.streaming) {
      cancelScheduledRender()
      displayedContent.value = props.content
    } else if (renderTimer === undefined) {
      // Parse at most once per interval, always using the latest complete text.
      renderTimer = setTimeout(() => {
        renderTimer = undefined
        displayedContent.value = props.content
      }, 50)
    }
  },
)

onBeforeUnmount(cancelScheduledRender)

const rendered = computed(() =>
  DOMPurify.sanitize(marked.parse(displayedContent.value) as string, {
    ADD_ATTR: ['target', 'rel'],
    FORBID_TAGS: ['style', 'form', 'input', 'button', 'iframe', 'script'],
  }),
)

async function copyCode(code: HTMLElement, button: HTMLButtonElement) {
  try {
    await navigator.clipboard.writeText(code.textContent ?? '')
    getUiApi().message.success('代码已复制。')
    button.textContent = '已复制'
    window.setTimeout(() => {
      if (button.isConnected) button.textContent = '复制'
    }, 1200)
  } catch (error) {
    console.error('Failed to copy code block', error)
    getUiApi().message.error('复制代码失败，请检查剪贴板权限。')
  }
}

function trimSingleLineTrailingBreak(code: HTMLElement) {
  const source = code.textContent ?? ''
  const content = source.replace(/(?:\r\n|\r|\n)+$/, '')
  if (!/[\r\n]/.test(content)) code.textContent = content
}

function enhanceCodeBlocks() {
  const root = markdownElement.value
  if (!root) return

  root.querySelectorAll<HTMLPreElement>('pre').forEach((pre) => {
    const code = pre.querySelector<HTMLElement>('code')
    if (!code || pre.querySelector('.agent-code-copy')) return

    trimSingleLineTrailingBreak(code)
    const language = [...code.classList]
      .find((name) => name.startsWith('language-'))
      ?.slice('language-'.length)
    const highlighted = highlightCode(code.textContent ?? '', language)
    if (highlighted !== undefined) code.innerHTML = DOMPurify.sanitize(highlighted)
    pre.classList.add('agent-code-block')

    const content = document.createElement('span')
    content.className = 'agent-code-content'
    const lineNumbers = document.createElement('span')
    lineNumbers.className = 'agent-code-line-numbers'
    lineNumbers.setAttribute('aria-hidden', 'true')
    const lines = (code.textContent ?? '').replace(/(?:\r\n|\r|\n)$/, '').split(/\r\n|\r|\n/)
    lineNumbers.textContent = lines.map((_, index) => index + 1).join('\n')
    code.replaceWith(content)
    content.append(lineNumbers, code)

    const button = document.createElement('button')
    button.type = 'button'
    button.className = 'agent-code-copy'
    button.setAttribute('aria-label', '复制代码')
    button.title = '复制代码'
    button.textContent = '复制'
    button.addEventListener('click', () => void copyCode(code, button))
    pre.append(button)
  })
}

function finishRender() {
  // Highlighting and code controls rebuild code DOM; do this once the model
  // turn ends instead of repeating it for every streamed fragment.
  if (!props.streaming) enhanceCodeBlocks()
  emit('rendered')
}

watch([rendered, () => props.streaming], finishRender, { flush: 'post' })

onMounted(finishRender)
</script>

<template>
  <div ref="markdownElement" class="agent-markdown" v-html="rendered" />
</template>

<style scoped>
.agent-markdown {
  overflow-wrap: anywhere;
  font-size: 13px;
  line-height: 1.78;
}

.agent-markdown :deep(> :first-child) {
  margin-top: 0;
}

.agent-markdown :deep(> :last-child) {
  margin-bottom: 0;
}

.agent-markdown :deep(p),
.agent-markdown :deep(ul),
.agent-markdown :deep(ol),
.agent-markdown :deep(blockquote),
.agent-markdown :deep(pre),
.agent-markdown :deep(table) {
  margin: 0 0 10px;
}

.agent-markdown :deep(h1),
.agent-markdown :deep(h2),
.agent-markdown :deep(h3),
.agent-markdown :deep(h4) {
  margin: 16px 0 8px;
  font-size: 13px;
  font-weight: 620;
}

.agent-markdown :deep(ul),
.agent-markdown :deep(ol) {
  padding-left: 20px;
}

.agent-markdown :deep(li) {
  margin: 2px 0;
}

.agent-markdown :deep(a) {
  color: var(--app-primary-color);
  text-decoration: underline;
  text-underline-offset: 2px;
}

.agent-markdown :deep(code) {
  padding: 1px 5px;
  border-radius: var(--app-radius-control);
  background: var(--agent-code-bg);
  font:
    12px/1.55 'Maple Mono',
    monospace;
}

.agent-markdown :deep(pre) {
  box-sizing: border-box;
  overflow-x: auto;
  overflow-y: hidden;
  padding: 12px 14px;
  border: 1px solid var(--agent-border);
  border-radius: var(--app-radius-item);
  color: var(--agent-code-text);
  background: var(--agent-code-bg);
  scrollbar-color: color-mix(in srgb, var(--agent-muted) 45%, transparent) transparent;
  scrollbar-width: thin;
}

.agent-markdown :deep(pre.agent-code-block) {
  position: relative;
  padding: 34px 14px 12px;
  box-shadow: inset 0 1px 0 color-mix(in srgb, var(--agent-text) 4%, transparent);
}

.agent-markdown :deep(.agent-code-content) {
  display: flex;
  gap: 12px;
  width: max-content;
  min-width: 100%;
  font:
    12px/1.55 'Maple Mono',
    monospace;
}

.agent-markdown :deep(.agent-code-line-numbers) {
  flex-shrink: 0;
  min-width: 2ch;
  padding-right: 12px;
  border-right: 1px solid var(--agent-border);
  color: var(--agent-muted);
  text-align: right;
  user-select: none;
}

.agent-markdown :deep(.agent-code-content > code) {
  display: block;
  padding: 0;
  border-radius: 0;
  background: transparent;
  white-space: pre;
}

.agent-markdown :deep(code .hljs-comment),
.agent-markdown :deep(code .hljs-quote) {
  color: var(--agent-muted);
  font-style: italic;
}

.agent-markdown :deep(code .hljs-keyword),
.agent-markdown :deep(code .hljs-selector-tag),
.agent-markdown :deep(code .hljs-doctag),
.agent-markdown :deep(code .hljs-deletion) {
  color: var(--agent-code-keyword);
}

.agent-markdown :deep(code .hljs-string),
.agent-markdown :deep(code .hljs-regexp),
.agent-markdown :deep(code .hljs-template-tag),
.agent-markdown :deep(code .hljs-template-variable) {
  color: var(--agent-code-string);
}

.agent-markdown :deep(code .hljs-number),
.agent-markdown :deep(code .hljs-literal),
.agent-markdown :deep(code .hljs-attr),
.agent-markdown :deep(code .hljs-attribute),
.agent-markdown :deep(code .hljs-variable) {
  color: var(--agent-code-value);
}

.agent-markdown :deep(code .hljs-title),
.agent-markdown :deep(code .hljs-section) {
  color: var(--agent-code-title);
}

.agent-markdown :deep(code .hljs-built_in),
.agent-markdown :deep(code .hljs-type),
.agent-markdown :deep(code .hljs-symbol),
.agent-markdown :deep(code .hljs-bullet) {
  color: var(--agent-code-builtin);
}

.agent-markdown :deep(code .hljs-name),
.agent-markdown :deep(code .hljs-selector-class),
.agent-markdown :deep(code .hljs-selector-id),
.agent-markdown :deep(code .hljs-addition) {
  color: var(--agent-code-tag);
}

.agent-markdown :deep(code .hljs-meta) {
  color: var(--agent-code-value);
}

.agent-markdown :deep(code .hljs-emphasis) {
  font-style: italic;
}

.agent-markdown :deep(code .hljs-strong) {
  font-weight: 700;
}

.agent-markdown :deep(pre.agent-code-block::before) {
  position: absolute;
  inset: 0 0 auto;
  height: 29px;
  border-radius: var(--app-radius-item) var(--app-radius-item) 0 0;
  background: var(--agent-code-toolbar-bg);
  content: '';
  pointer-events: none;
}

.agent-markdown :deep(pre.agent-code-block::after) {
  position: absolute;
  top: 28px;
  right: 0;
  left: 0;
  height: 1px;
  background: var(--agent-border);
  content: '';
  pointer-events: none;
}

.agent-markdown :deep(.agent-code-copy) {
  position: absolute;
  top: 3px;
  right: 9px;
  z-index: 1;
  display: inline-flex;
  min-height: 22px;
  align-items: center;
  padding: 2px 7px;
  border: 0;
  border-radius: var(--app-radius-control);
  background: transparent;
  color: var(--agent-code-toolbar-text);
  cursor: pointer;
  font: inherit;
  font-size: 11px;
  font-weight: 600;
  line-height: 1.5;
  user-select: none;
  transition:
    color 150ms ease,
    background-color 150ms ease;
}

.agent-markdown :deep(.agent-code-copy:hover) {
  background: var(--agent-code-toolbar-bg);
  color: var(--agent-code-toolbar-text);
}

.agent-markdown :deep(.agent-code-copy:focus-visible) {
  outline: 2px solid var(--app-primary-color);
  outline-offset: 1px;
}

.agent-markdown :deep(blockquote) {
  padding: 2px 0 2px 12px;
  border-left: 3px solid var(--agent-border);
  color: var(--agent-muted);
}

.agent-markdown :deep(table) {
  display: block;
  width: 100%;
  overflow: auto;
  border-collapse: collapse;
}

.agent-markdown :deep(th),
.agent-markdown :deep(td) {
  padding: 5px 10px;
  border: 1px solid var(--agent-border);
  text-align: left;
  white-space: nowrap;
}

.agent-markdown :deep(th) {
  background: var(--agent-tool-bg);
  font-weight: 600;
}

.agent-markdown :deep(hr) {
  margin: 14px 0;
  border: 0;
  border-top: 1px solid var(--agent-border);
}
</style>

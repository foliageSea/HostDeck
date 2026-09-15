<script setup lang="ts">
import { computed } from 'vue'
import DOMPurify from 'dompurify'
import { marked } from 'marked'

const props = defineProps<{
  content: string
}>()

DOMPurify.addHook('afterSanitizeAttributes', (node) => {
  if (node.tagName === 'A') {
    node.setAttribute('target', '_blank')
    node.setAttribute('rel', 'noopener noreferrer nofollow')
  }
})

marked.setOptions({ breaks: true, gfm: true })

const rendered = computed(() =>
  DOMPurify.sanitize(marked.parse(props.content) as string, {
    ADD_ATTR: ['target', 'rel'],
    FORBID_TAGS: ['style', 'form', 'input', 'button', 'iframe', 'script'],
  }),
)
</script>

<template>
  <div class="agent-markdown" v-html="rendered" />
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
  overflow: auto;
  padding: 10px 12px;
  border: 1px solid var(--agent-border);
  border-radius: var(--app-radius-item);
  background: var(--agent-code-bg);
}

.agent-markdown :deep(pre code) {
  padding: 0;
  background: transparent;
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

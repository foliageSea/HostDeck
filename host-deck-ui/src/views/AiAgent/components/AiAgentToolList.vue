<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { PlugZap, RefreshCw, Search, ShieldCheck, Wrench } from '@lucide/vue'
import { getUiApi } from '@/lib/ui'
import { useAiAgentStore } from '@/stores/ai-agent'

const store = useAiAgentStore()
const query = ref('')
const props = defineProps<{ active: boolean }>()

const labels: Record<string, { description: string; title: string }> = {
  apply_patch: { description: '在远程工作目录应用 Git Patch', title: '应用补丁' },
  directory_list: { description: '查看远程目录中的文件和子目录', title: '浏览目录' },
  file_delete: { description: '删除单个远程文件，不会删除目录', title: '删除文件' },
  file_read: { description: '读取远程文本文件内容', title: '读取文件' },
  file_write: { description: '覆盖写入远程文本文件', title: '写入文件' },
  process_kill: { description: '向远程进程发送 SIGTERM', title: '结束进程' },
  process_list: { description: '读取按 CPU 和内存排序的进程列表', title: '进程列表' },
  shell_execute: { description: '在远程主机执行 Shell 命令', title: '执行命令' },
  system_status: { description: '读取 CPU、内存、磁盘、网络和系统状态', title: '系统状态' },
}

const filteredTools = computed(() => {
  const keyword = query.value.trim().toLocaleLowerCase()
  if (!keyword) return store.tools
  return store.tools.filter((tool) => {
    const label = labels[tool.name]
    return [tool.name, tool.description, label?.title, label?.description].some((value) =>
      value?.toLocaleLowerCase().includes(keyword),
    )
  })
})

const builtInCount = computed(() => store.tools.filter((tool) => tool.source === 'built-in').length)
const mcpCount = computed(() => store.tools.filter((tool) => tool.source === 'mcp').length)

function title(name: string) {
  return labels[name]?.title ?? name
}

function description(name: string, fallback: string) {
  return labels[name]?.description ?? fallback
}

function argumentNames(schema: Record<string, unknown>) {
  const properties = schema.properties
  if (!properties || typeof properties !== 'object' || Array.isArray(properties)) return []
  return Object.keys(properties)
}

async function load() {
  try {
    await store.loadTools()
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '加载工具列表失败。')
  }
}

watch(
  () => props.active,
  (active) => {
    if (active) void load()
  },
  { immediate: true },
)
</script>

<template>
  <div class="agent-tool-list-view">
    <div class="agent-tool-list-toolbar">
      <div class="agent-tool-list-counts">
        <span>内置 {{ builtInCount }}</span>
        <span>MCP {{ mcpCount }}</span>
      </div>
      <div class="agent-tool-list-actions">
        <NInput v-model:value="query" clearable size="small" placeholder="搜索工具">
          <template #prefix><Search :size="14" /></template>
        </NInput>
        <NButton quaternary circle size="small" :loading="store.loadingTools" aria-label="刷新工具列表" @click="load">
          <template #icon><RefreshCw :size="14" /></template>
        </NButton>
      </div>
    </div>

    <div v-if="store.loadingTools && store.tools.length === 0" class="agent-tool-list-state">
      <NSpin size="small" />
      <span>正在发现可用工具</span>
    </div>
    <div v-else-if="filteredTools.length === 0" class="agent-tool-list-state">
      <Wrench :size="28" />
      <span>{{ query ? '没有匹配的工具' : '没有可用工具' }}</span>
    </div>
    <div v-else class="agent-tool-list-items app-scrollbar">
      <article v-for="tool in filteredTools" :key="tool.name" class="agent-tool-list-item">
        <div class="agent-tool-list-icon" :class="{ 'agent-tool-list-icon-mcp': tool.source === 'mcp' }">
          <PlugZap v-if="tool.source === 'mcp'" :size="16" />
          <Wrench v-else :size="16" />
        </div>
        <div class="agent-tool-list-copy">
          <div class="agent-tool-list-title">
            <strong>{{ title(tool.name) }}</strong>
            <code>{{ tool.name }}</code>
          </div>
          <p :title="description(tool.name, tool.description)">
            {{ description(tool.name, tool.description) }}
          </p>
          <div class="agent-tool-list-meta">
            <span>{{ tool.source === 'mcp' ? 'MCP 工具' : '内置工具' }}</span>
            <span v-if="tool.requiresApproval" class="agent-tool-list-approval">
              <ShieldCheck :size="12" /> 执行前需批准
            </span>
            <span v-else class="agent-tool-list-direct">可直接执行</span>
            <span v-for="argument in argumentNames(tool.inputSchema)" :key="argument" class="agent-tool-list-argument">
              {{ argument }}
            </span>
          </div>
        </div>
      </article>
    </div>
  </div>
</template>

<style scoped>
.agent-tool-list-view {
  min-height: 300px;
}
.agent-tool-list-toolbar,
.agent-tool-list-counts,
.agent-tool-list-actions,
.agent-tool-list-title,
.agent-tool-list-meta {
  display: flex;
  align-items: center;
}
.agent-tool-list-toolbar {
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
}
.agent-tool-list-counts,
.agent-tool-list-meta {
  flex-wrap: wrap;
  gap: 6px;
}
.agent-tool-list-counts {
  color: var(--n-text-color-3);
  font-size: 11px;
}
.agent-tool-list-actions {
  width: min(260px, 60%);
  gap: 4px;
}
.agent-tool-list-state {
  display: grid;
  min-height: 260px;
  place-content: center;
  justify-items: center;
  gap: 9px;
  color: var(--n-text-color-3);
  font-size: 12px;
}
.agent-tool-list-items {
  display: grid;
  max-height: 410px;
  overflow: auto;
}
.agent-tool-list-item {
  display: flex;
  min-width: 0;
  gap: 10px;
  padding: 12px 4px;
  border-bottom: 1px solid var(--agent-border, rgba(100, 116, 139, 0.18));
}
.agent-tool-list-icon {
  display: grid;
  width: 32px;
  height: 32px;
  flex: 0 0 auto;
  place-items: center;
  border-radius: 9px;
  background: color-mix(in srgb, var(--n-color-target, #2080f0) 10%, transparent);
  color: var(--n-color-target, #2080f0);
}
.agent-tool-list-icon-mcp {
  background: rgba(139, 92, 246, 0.1);
  color: #8b5cf6;
}
.agent-tool-list-copy {
  min-width: 0;
  flex: 1;
}
.agent-tool-list-title {
  min-width: 0;
  gap: 8px;
}
.agent-tool-list-title strong {
  font-size: 13px;
}
.agent-tool-list-title code {
  overflow: hidden;
  color: var(--n-text-color-3);
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.agent-tool-list-copy p {
  display: -webkit-box;
  overflow: hidden;
  margin: 4px 0 7px;
  color: var(--n-text-color-2);
  font-size: 11px;
  line-height: 1.5;
  text-overflow: ellipsis;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}
.agent-tool-list-meta span {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  padding: 2px 6px;
  border-radius: 999px;
  background: var(--n-color-embedded);
  color: var(--n-text-color-3);
  font-size: 9px;
}
.agent-tool-list-meta .agent-tool-list-approval {
  color: #d97706;
}
.agent-tool-list-meta .agent-tool-list-direct {
  color: #16a34a;
}
.agent-tool-list-meta .agent-tool-list-argument {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
}
@media (max-width: 520px) {
  .agent-tool-list-toolbar {
    align-items: stretch;
    flex-direction: column;
  }
  .agent-tool-list-actions {
    width: 100%;
  }
}
</style>

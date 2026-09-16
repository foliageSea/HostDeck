<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { CirclePlus, Pencil, PlugZap, Server, Trash2 } from '@lucide/vue'
import type { AiAgentMcpServer, AiAgentMcpServerInput } from '@/api/ai-agent'
import { getUiApi } from '@/lib/ui'
import { useAiAgentStore } from '@/stores/ai-agent'
import { parseMcpConfig } from './mcp-config'

const store = useAiAgentStore()
const editorOpen = ref(false)
const saving = ref(false)
const testingId = ref<number | null>(null)
const editingId = ref<number | null>(null)
const clearHeaders = ref(false)
const form = reactive({ enabled: true, headers: '', name: '', url: '' })
const usesPlainHttp = computed(() => /^http:\/\//i.test(form.url.trim()))

onMounted(async () => {
  if (store.mcpServers.length === 0 && !store.loadingMcpServers) {
    try {
      await store.loadMcpServers()
    } catch (error) {
      getUiApi().message.error(error instanceof Error ? error.message : '加载 MCP 服务器失败。')
    }
  }
})

function openEditor(server?: AiAgentMcpServer) {
  editingId.value = server?.id ?? null
  form.name = server?.name ?? ''
  form.url = server?.url ?? ''
  form.enabled = server?.enabled ?? true
  form.headers = ''
  clearHeaders.value = false
  editorOpen.value = true
}

function parseConfigInput() {
  const source = form.headers.trim()
  if (!source) return undefined
  const parsed = parseMcpConfig(source)
  if (parsed.url) form.url = parsed.url
  if (parsed.name && !form.name.trim()) form.name = parsed.name
  return parsed.headers
}

async function save() {
  let headers: Record<string, string> | undefined
  try {
    headers = parseConfigInput()
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : 'MCP 配置格式无效。')
    return
  }
  if (!form.name.trim() || !form.url.trim()) {
    getUiApi().message.warning('请填写名称和 MCP URL。')
    return
  }
  const payload: AiAgentMcpServerInput = {
    enabled: form.enabled,
    name: form.name.trim(),
    url: form.url.trim(),
    ...(headers ? { headers } : {}),
    ...(clearHeaders.value ? { clearHeaders: true } : {}),
  }
  saving.value = true
  try {
    if (editingId.value === null) await store.createMcpServer(payload)
    else await store.updateMcpServer(editingId.value, payload)
    editorOpen.value = false
    getUiApi().message.success('MCP 服务器已保存。')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '保存 MCP 服务器失败。')
  } finally {
    saving.value = false
  }
}

async function toggle(server: AiAgentMcpServer, enabled: boolean) {
  try {
    await store.updateMcpServer(server.id, {
      enabled,
      name: server.name,
      url: server.url,
    })
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '更新 MCP 服务器失败。')
  }
}

async function test(server: AiAgentMcpServer) {
  testingId.value = server.id
  try {
    const result = await store.testMcpServer(server.id)
    getUiApi().message.success(`连接成功，发现 ${result.toolCount} 个工具。`)
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : 'MCP 连接测试失败。')
  } finally {
    testingId.value = null
  }
}

function remove(server: AiAgentMcpServer) {
  const dialog = getUiApi().dialog.warning({
    title: '删除 MCP 服务器',
    content: `确认删除“${server.name}”？`,
    positiveText: '删除',
    negativeText: '取消',
    onPositiveClick: async () => {
      dialog.loading = true
      try {
        await store.deleteMcpServer(server.id)
      } catch (error) {
        getUiApi().message.error(error instanceof Error ? error.message : '删除 MCP 服务器失败。')
      } finally {
        dialog.loading = false
      }
    },
  })
}
</script>

<template>
  <div class="agent-mcp-settings">
    <div class="agent-mcp-toolbar">
      <span>{{ store.mcpServers.length }} 个服务器</span>
      <NButton size="small" type="primary" @click="openEditor()">
        <template #icon><CirclePlus :size="15" /></template>
        添加服务器
      </NButton>
    </div>

    <div v-if="store.loadingMcpServers" class="agent-mcp-state"><NSpin size="small" /></div>
    <div v-else-if="store.mcpServers.length === 0" class="agent-mcp-state">
      <Server :size="28" />
      <span>尚未配置 MCP 服务器</span>
    </div>
    <div v-else class="agent-mcp-list app-scrollbar">
      <div v-for="server in store.mcpServers" :key="server.id" class="agent-mcp-row">
        <div class="agent-mcp-status" :class="{ 'agent-mcp-status-enabled': server.enabled }">
          <PlugZap :size="15" />
        </div>
        <div class="agent-mcp-copy">
          <strong>{{ server.name }}</strong>
          <small>{{ server.url }}</small>
        </div>
        <NSwitch
          size="small"
          :value="server.enabled"
          :aria-label="`${server.enabled ? '停用' : '启用'} ${server.name}`"
          @update:value="toggle(server, $event)"
        />
        <NButton
          quaternary
          size="tiny"
          :loading="testingId === server.id"
          :disabled="testingId !== null"
          @click="test(server)"
        >
          测试
        </NButton>
        <NButton
          quaternary
          circle
          size="tiny"
          :aria-label="`编辑 ${server.name}`"
          @click="openEditor(server)"
        >
          <template #icon><Pencil :size="14" /></template>
        </NButton>
        <NButton
          quaternary
          circle
          size="tiny"
          type="error"
          :aria-label="`删除 ${server.name}`"
          @click="remove(server)"
        >
          <template #icon><Trash2 :size="14" /></template>
        </NButton>
      </div>
    </div>

    <NModal
      v-model:show="editorOpen"
      preset="card"
      :title="editingId === null ? '添加 MCP 服务器' : '编辑 MCP 服务器'"
      class="agent-mcp-editor"
      :bordered="false"
    >
      <NForm label-placement="top">
        <NFormItem label="名称">
          <NInput v-model:value="form.name" maxlength="60" placeholder="例如 GitHub" />
        </NFormItem>
        <NFormItem label="Streamable HTTP URL">
          <div class="w-full">
            <NInput v-model:value="form.url" placeholder="https://example.com/mcp" />
            <div v-if="usesPlainHttp" class="mt-2 text-[11px] text-amber-500">
              HTTP 不会加密 MCP 请求，仅用于可信网络。
            </div>
          </div>
        </NFormItem>
        <NFormItem label="请求头或完整 MCP 配置 JSON">
          <div class="w-full">
            <NInput
              v-model:value="form.headers"
              type="textarea"
              :autosize="{ minRows: 3, maxRows: 6 }"
              placeholder='{ "type": "sse", "url": "https://example.com/mcp", "headers": { "Authorization": "Bearer ..." } }'
            />
            <div class="mt-2 flex items-center justify-between gap-3 text-[11px] opacity-60">
              <span>{{
                editingId === null
                  ? '支持完整配置或纯请求头，请求头将加密保存'
                  : '留空以保留现有请求头'
              }}</span>
              <NCheckbox v-if="editingId !== null" v-model:checked="clearHeaders"
                >清除现有请求头</NCheckbox
              >
            </div>
          </div>
        </NFormItem>
        <NFormItem label="状态">
          <NSwitch v-model:value="form.enabled">
            <template #checked>启用</template>
            <template #unchecked>停用</template>
          </NSwitch>
        </NFormItem>
      </NForm>
      <template #footer>
        <div class="flex justify-end gap-2">
          <NButton @click="editorOpen = false">取消</NButton>
          <NButton type="primary" :loading="saving" @click="save">保存</NButton>
        </div>
      </template>
    </NModal>
  </div>
</template>

<style scoped>
.agent-mcp-settings {
  min-height: 300px;
}
.agent-mcp-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 12px;
  color: var(--agent-muted, #64748b);
  font-size: 11px;
}
.agent-mcp-list {
  max-height: 360px;
  overflow: auto;
}
.agent-mcp-row {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 8px;
  min-height: 52px;
  padding: 7px 4px;
  border-bottom: 1px solid var(--agent-border, rgba(100, 116, 139, 0.18));
}
.agent-mcp-status {
  display: grid;
  width: 30px;
  height: 30px;
  flex: 0 0 auto;
  place-items: center;
  border-radius: var(--app-radius-control);
  color: #64748b;
  background: rgba(100, 116, 139, 0.1);
}
.agent-mcp-status-enabled {
  color: #16a34a;
  background: rgba(22, 163, 74, 0.1);
}
.agent-mcp-copy {
  min-width: 0;
  flex: 1;
}
.agent-mcp-copy strong,
.agent-mcp-copy small {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.agent-mcp-copy strong {
  font-size: 12px;
  font-weight: 600;
}
.agent-mcp-copy small {
  margin-top: 2px;
  opacity: 0.55;
  font-size: 10px;
}
.agent-mcp-state {
  display: flex;
  min-height: 260px;
  align-items: center;
  justify-content: center;
  flex-direction: column;
  gap: 9px;
  opacity: 0.52;
  font-size: 11px;
}
:global(.agent-mcp-editor) {
  width: min(520px, calc(100vw - 28px));
}
@media (max-width: 520px) {
  .agent-mcp-row {
    flex-wrap: wrap;
  }
  .agent-mcp-copy {
    flex-basis: calc(100% - 46px);
  }
}
</style>

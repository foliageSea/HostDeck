<script setup lang="ts">
import { reactive, ref, watch } from 'vue'
import { terminalApi, type TerminalSnippet } from '@/api/terminal'
import { getUiApi } from '@/lib/ui'

const props = defineProps<{
  show: boolean
}>()

const emit = defineEmits<{
  'update:show': [value: boolean]
  select: [command: string]
}>()

const snippets = ref<TerminalSnippet[]>([])
const loading = ref(false)
const saving = ref(false)
const editingId = ref<number | null>(null)
const editorVisible = ref(false)
const form = reactive({
  command: '',
  name: '',
})
const snippetActionOptions = [
  { key: 'edit', label: '编辑' },
  { key: 'remove', label: '删除' },
]

function resetForm() {
  editingId.value = null
  form.command = ''
  form.name = ''
}

async function loadSnippets() {
  loading.value = true
  try {
    snippets.value = await terminalApi.listSnippets()
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '加载命令片段失败。')
  } finally {
    loading.value = false
  }
}

function openCreateEditor() {
  resetForm()
  editorVisible.value = true
}

function openEditEditor(snippet: TerminalSnippet) {
  editingId.value = snippet.id
  form.command = snippet.command
  form.name = snippet.name
  editorVisible.value = true
}

async function saveSnippet() {
  const name = form.name.trim()
  const command = form.command.trim()
  if (!name) {
    getUiApi().message.warning('请输入片段名称。')
    return
  }
  if (!command) {
    getUiApi().message.warning('请输入命令。')
    return
  }

  saving.value = true
  try {
    const payload = { name, command }
    const snippet =
      editingId.value === null
        ? await terminalApi.createSnippet(payload)
        : await terminalApi.updateSnippet(editingId.value, payload)
    const index = snippets.value.findIndex((item) => item.id === snippet.id)
    if (index === -1) {
      snippets.value.unshift(snippet)
    } else {
      snippets.value[index] = snippet
    }
    editorVisible.value = false
    getUiApi().message.success('命令片段已保存。')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '保存命令片段失败。')
  } finally {
    saving.value = false
  }
}

function removeSnippet(snippet: TerminalSnippet) {
  getUiApi().dialog.warning({
    content: `删除后将无法恢复“${snippet.name}”。`,
    negativeText: '取消',
    positiveText: '删除',
    title: '删除命令片段',
    onPositiveClick: async () => {
      try {
        await terminalApi.deleteSnippet(snippet.id)
        snippets.value = snippets.value.filter((item) => item.id !== snippet.id)
        getUiApi().message.success('命令片段已删除。')
      } catch (error) {
        getUiApi().message.error(error instanceof Error ? error.message : '删除命令片段失败。')
      }
    },
  })
}

function handleSnippetAction(snippet: TerminalSnippet, key: string | number) {
  if (key === 'edit') {
    openEditEditor(snippet)
    return
  }

  if (key === 'remove') {
    removeSnippet(snippet)
  }
}

function selectSnippet(snippet: TerminalSnippet) {
  emit('select', snippet.command)
  emit('update:show', false)
}

watch(
  () => props.show,
  (show) => {
    if (show) {
      void loadSnippets()
      return
    }

    editorVisible.value = false
  },
)
</script>

<template>
  <NModal
    :show="show"
    preset="card"
    title="命令片段"
    style="width: min(680px, calc(100vw - 24px))"
    @update:show="(value: boolean) => emit('update:show', value)"
  >
    <template #header-extra>
      <NButton size="small" secondary @click="openCreateEditor">新增片段</NButton>
    </template>

    <div v-if="loading" class="flex min-h-[220px] items-center justify-center">
      <NSpin size="large" />
    </div>
    <NEmpty v-else-if="snippets.length === 0" class="py-[48px]" description="暂无命令片段">
      <template #extra>
        <NButton size="small" secondary @click="openCreateEditor">新增第一个片段</NButton>
      </template>
    </NEmpty>
    <div
      v-else
      class="max-h-[min(56vh,520px)] overflow-auto divide-y divide-[rgba(148,163,184,0.16)]"
    >
      <div v-for="snippet in snippets" :key="snippet.id" class="py-[14px] first:pt-0 last:pb-0">
        <div class="flex items-start justify-between gap-[12px]">
          <div class="min-w-0 flex-1">
            <div class="truncate text-[14px] font-600">{{ snippet.name }}</div>
            <pre
              class="mt-[7px] max-h-[88px] overflow-auto whitespace-pre-wrap break-all rounded-[6px] bg-[rgba(148,163,184,0.1)] px-[10px] py-[8px] text-[12px] leading-[1.55]"
              >{{ snippet.command }}</pre
            >
          </div>
          <NSpace size="small" class="mt-[27px] shrink-0 self-start">
            <NButton size="small" secondary @click="selectSnippet(snippet)">填入</NButton>
            <NDropdown
              trigger="click"
              :options="snippetActionOptions"
              @select="(key: string | number) => handleSnippetAction(snippet, key)"
            >
              <NButton size="small" secondary>操作</NButton>
            </NDropdown>
          </NSpace>
        </div>
      </div>
    </div>
  </NModal>

  <NModal
    v-model:show="editorVisible"
    preset="card"
    :title="editingId === null ? '新增命令片段' : '编辑命令片段'"
    style="width: min(580px, calc(100vw - 24px))"
  >
    <NForm label-placement="top">
      <NFormItem label="名称">
        <NInput v-model:value="form.name" maxlength="80" placeholder="查看 Docker 日志" />
      </NFormItem>
      <NFormItem label="命令">
        <NInput
          v-model:value="form.command"
          type="textarea"
          :autosize="{ minRows: 5, maxRows: 12 }"
          placeholder="输入要填入终端的命令"
        />
      </NFormItem>
    </NForm>
    <template #footer>
      <div class="flex justify-end gap-[10px]">
        <NButton @click="editorVisible = false">取消</NButton>
        <NButton type="primary" :loading="saving" @click="saveSnippet">保存</NButton>
      </div>
    </template>
  </NModal>
</template>

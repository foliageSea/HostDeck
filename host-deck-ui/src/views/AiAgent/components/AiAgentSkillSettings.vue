<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { FileCode2, Plus, Save, Trash2 } from '@lucide/vue'
import type { AiAgentSkill } from '@/api/ai-agent'
import CodeEditor from '@/components/editor/CodeEditor.vue'
import { getUiApi } from '@/lib/ui'
import { useAiAgentStore } from '@/stores/ai-agent'

const NEW_SKILL_TEMPLATE = `---
name: new-skill
description: Describe when and how this skill should be used.
---

# New Skill

Add instructions for the agent here.
`

const store = useAiAgentStore()
const editingId = ref<number | null>(null)
const editingName = ref('')
const content = ref('')
const savedContent = ref('')
const loadingDetail = ref(false)
const saving = ref(false)
const loadRequest = ref(0)
const hasEditor = ref(false)
const dirty = computed(() => hasEditor.value && content.value !== savedContent.value)

defineExpose({ dirty })

function confirmDiscard(action: () => void) {
  if (!dirty.value) {
    action()
    return
  }
  getUiApi().dialog.warning({
    title: '放弃未保存的修改',
    content: '当前 SKILL.md 尚未保存，确认放弃修改？',
    positiveText: '放弃修改',
    negativeText: '继续编辑',
    onPositiveClick: action,
  })
}

onMounted(async () => {
  try {
    await store.loadManagedSkills()
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '加载 Skills 失败。')
  }
})

function numericId(skill: AiAgentSkill) {
  const match = /^hostdeck:(\d+)$/.exec(skill.id)
  return match && skill.editable ? Number(match[1]) : null
}

function createSkill() {
  confirmDiscard(startCreateSkill)
}

function startCreateSkill() {
  loadRequest.value++
  if (saving.value) return
  loadingDetail.value = false
  editingId.value = null
  editingName.value = ''
  content.value = NEW_SKILL_TEMPLATE
  savedContent.value = NEW_SKILL_TEMPLATE
  hasEditor.value = true
}

function editSkill(skill: AiAgentSkill) {
  if (skill.id === `hostdeck:${editingId.value}` && hasEditor.value) return
  confirmDiscard(() => void loadSkill(skill))
}

async function loadSkill(skill: AiAgentSkill) {
  const id = numericId(skill)
  if (id === null || loadingDetail.value || saving.value) return
  const request = ++loadRequest.value
  loadingDetail.value = true
  hasEditor.value = false
  try {
    const detail = await store.getManagedSkill(id)
    if (request !== loadRequest.value) return
    editingId.value = id
    editingName.value = detail.name
    content.value = detail.content
    savedContent.value = detail.content
    hasEditor.value = true
  } catch (error) {
    if (request === loadRequest.value) hasEditor.value = Boolean(content.value)
    getUiApi().message.error(error instanceof Error ? error.message : '加载 Skill 详情失败。')
  } finally {
    if (request === loadRequest.value) loadingDetail.value = false
  }
}

async function save() {
  if (saving.value || !content.value.trim()) {
    if (!content.value.trim()) getUiApi().message.warning('SKILL.md 内容不能为空。')
    return
  }
  saving.value = true
  const submittedContent = content.value
  try {
    const skill =
      editingId.value === null
        ? await store.createManagedSkill(submittedContent)
        : await store.updateManagedSkill(editingId.value, submittedContent)
    const id = numericId(skill)
    if (id !== null) editingId.value = id
    editingName.value = skill.name
    savedContent.value = skill.content
    if (content.value === submittedContent) content.value = skill.content
    getUiApi().message.success('Skill 已保存。')
  } catch (error) {
    getUiApi().message.error(error instanceof Error ? error.message : '保存 Skill 失败。')
  } finally {
    saving.value = false
  }
}

function remove(skill: AiAgentSkill) {
  const id = numericId(skill)
  if (id === null) return
  const dialog = getUiApi().dialog.warning({
    title: '删除 Skill',
    content: `确认删除“${skill.name}”？`,
    positiveText: '删除',
    negativeText: '取消',
    onPositiveClick: async () => {
      dialog.loading = true
      try {
        await store.deleteManagedSkill(id)
        if (editingId.value === id) {
          editingId.value = null
          content.value = ''
          savedContent.value = ''
          hasEditor.value = false
        }
        getUiApi().message.success('Skill 已删除。')
      } catch (error) {
        getUiApi().message.error(error instanceof Error ? error.message : '删除 Skill 失败。')
      } finally {
        dialog.loading = false
      }
    },
  })
}
</script>

<template>
  <div class="agent-skill-settings">
    <aside class="agent-skill-library">
      <div class="agent-skill-library-toolbar">
        <span>{{ store.managedSkills.length }} 个 Skills</span>
        <NButton size="small" type="primary" :disabled="saving" @click="createSkill">
          <template #icon><Plus :size="15" /></template>
          新建
        </NButton>
      </div>

      <div v-if="store.loadingManagedSkills" class="agent-skill-library-state">
        <NSpin size="small" />
      </div>
      <div v-else-if="store.managedSkills.length === 0" class="agent-skill-library-state">
        <FileCode2 :size="28" />
        <span>尚未创建数据库 Skill</span>
      </div>
      <div v-else class="agent-skill-library-list app-scrollbar app-scrollbar-compact">
        <div
          v-for="skill in store.managedSkills"
          :key="skill.id"
          class="agent-skill-library-row"
          :class="{ 'agent-skill-library-row-active': numericId(skill) === editingId }"
        >
          <button
            type="button"
            class="agent-skill-library-copy"
            :aria-pressed="numericId(skill) === editingId && hasEditor"
            :disabled="loadingDetail || saving"
            @click="editSkill(skill)"
          >
            <strong>{{ skill.name }}</strong>
            <small>{{ skill.description }}</small>
          </button>
          <NButton
            quaternary
            circle
            size="tiny"
            type="error"
            :aria-label="`删除 ${skill.name}`"
            @click="remove(skill)"
          >
            <template #icon><Trash2 :size="14" /></template>
          </NButton>
        </div>
      </div>
    </aside>

    <section class="agent-skill-editor-pane">
      <div v-if="hasEditor" class="agent-skill-editor-workspace">
        <div class="agent-skill-editor-toolbar">
          <span>{{ editingId === null ? '新建 SKILL.md' : editingName }}</span>
          <NButton size="small" type="primary" :loading="saving" :disabled="loadingDetail || (editingId !== null && content === savedContent)" @click="save">
            <template #icon><Save :size="14" /></template>
            保存
          </NButton>
        </div>
        <CodeEditor v-model="content" language="markdown" class="agent-skill-markdown-editor" />
      </div>
      <div v-else class="agent-skill-editor-state">
        <NSpin v-if="loadingDetail" size="small" />
        <template v-else>
          <FileCode2 :size="32" />
          <span>选择一个 Skill 编辑，或新建 SKILL.md</span>
        </template>
      </div>
    </section>
  </div>
</template>

<style scoped>
.agent-skill-settings {
  display: grid;
  min-height: 460px;
  grid-template-columns: minmax(210px, 0.34fr) minmax(0, 1fr);
  gap: 14px;
}

.agent-skill-library {
  min-width: 0;
  border-right: 1px solid var(--agent-border, rgba(100, 116, 139, 0.18));
  padding-right: 14px;
}

.agent-skill-library-toolbar,
.agent-skill-editor-toolbar {
  display: flex;
  min-height: 32px;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 10px;
  color: var(--agent-muted, #64748b);
  font-size: 11px;
}

.agent-skill-library-list {
  max-height: 418px;
  overflow-y: auto;
}

.agent-skill-library-row {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 7px 4px 7px 8px;
  border-radius: var(--app-radius-item);
}

.agent-skill-library-row:hover,
.agent-skill-library-row-active {
  background: var(--agent-hover, rgba(100, 116, 139, 0.09));
}

.agent-skill-library-copy {
  min-width: 0;
  flex: 1;
  padding: 0;
  border: 0;
  color: inherit;
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.agent-skill-library-copy strong,
.agent-skill-library-copy small {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.agent-skill-library-copy strong {
  font-size: 12px;
  font-weight: 600;
}

.agent-skill-library-copy small {
  margin-top: 3px;
  color: var(--agent-muted, #64748b);
  font-size: 10px;
}

.agent-skill-library-state,
.agent-skill-editor-state {
  display: flex;
  min-height: 360px;
  align-items: center;
  justify-content: center;
  flex-direction: column;
  gap: 9px;
  color: var(--agent-muted, #64748b);
  text-align: center;
  font-size: 11px;
}

.agent-skill-editor-pane,
.agent-skill-editor-workspace {
  min-width: 0;
  min-height: 0;
}

.agent-skill-editor-workspace {
  display: grid;
  height: 460px;
  grid-template-rows: auto minmax(0, 1fr);
}

.agent-skill-markdown-editor {
  min-height: 0;
}

@media (max-width: 680px) {
  .agent-skill-settings {
    min-height: 0;
    grid-template-columns: 1fr;
    gap: 8px;
  }

  .agent-skill-library {
    border-right: 0;
    border-bottom: 1px solid var(--agent-border, rgba(100, 116, 139, 0.18));
    padding-right: 0;
    padding-bottom: 12px;
  }

  .agent-skill-library-list {
    max-height: min(120px, 20vh);
  }

  .agent-skill-library-state {
    min-height: 100px;
  }

  .agent-skill-editor-workspace {
    height: clamp(180px, 36vh, 320px);
  }
}
</style>

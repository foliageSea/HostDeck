<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { Puzzle, RefreshCw, Search, Settings } from '@lucide/vue'
import { MAX_SELECTED_SKILLS, useAiAgentStore } from '@/stores/ai-agent'

const props = defineProps<{
  connectionId: string | null
  disabled?: boolean
}>()

const emit = defineEmits<{
  manage: []
}>()

const store = useAiAgentStore()
const { loadingSkills, selectedSkillIds, skills, skillsError } = storeToRefs(store)
const query = ref('')
const popoverOpen = ref(false)

const filteredSkills = computed(() => {
  const keyword = query.value.trim().toLocaleLowerCase()
  if (!keyword) return skills.value
  return skills.value.filter((skill) =>
    [skill.name, skill.description, skill.source].some((value) =>
      value.toLocaleLowerCase().includes(keyword),
    ),
  )
})

function refresh() {
  if (props.connectionId && !props.disabled) {
    void store.loadSkills(props.connectionId).catch(() => undefined)
  }
}

function updateSkill(id: string, checked: boolean) {
  if (props.disabled) return
  store.setSelectedSkillIds(
    checked
      ? [...selectedSkillIds.value, id]
      : selectedSkillIds.value.filter((selectedId) => selectedId !== id),
  )
}

function skillDisabled(id: string) {
  return (
    Boolean(props.disabled) ||
    (selectedSkillIds.value.length >= MAX_SELECTED_SKILLS && !selectedSkillIds.value.includes(id))
  )
}
</script>

<template>
  <NPopover
    v-model:show="popoverOpen"
    trigger="click"
    placement="top-start"
    :show-arrow="false"
    :disabled="!connectionId"
  >
    <template #trigger>
      <button
        type="button"
        class="agent-skill-trigger"
        :class="{ 'agent-skill-trigger-active': selectedSkillIds.length > 0 }"
        :disabled="!connectionId || disabled"
        aria-label="选择 Agent Skill"
      >
        <Puzzle :size="13" />
        <span>Skills</span>
        <strong v-if="selectedSkillIds.length">{{ selectedSkillIds.length }}</strong>
      </button>
    </template>

    <div class="agent-skill-picker">
      <div class="agent-skill-header">
        <div class="agent-skill-title">Agent Skills</div>
        <div class="agent-skill-header-actions">
          <button
            type="button"
            class="agent-skill-refresh"
            aria-label="管理 Agent Skills"
            title="管理"
            @click="popoverOpen = false; emit('manage')"
          >
            <Settings :size="14" />
          </button>
          <button
            type="button"
            class="agent-skill-refresh"
            :disabled="loadingSkills || disabled"
            aria-label="刷新 Agent Skills"
            title="刷新"
            @click="refresh"
          >
            <RefreshCw :size="14" :class="{ 'agent-skill-spinning': loadingSkills }" />
          </button>
        </div>
      </div>

      <label class="agent-skill-search">
        <Search :size="13" />
        <input
          v-model="query"
          type="search"
          placeholder="搜索 Skill"
          aria-label="搜索 Agent Skill"
        />
      </label>

      <div class="agent-skill-list app-scrollbar app-scrollbar-compact">
        <div v-if="loadingSkills && skills.length === 0" class="agent-skill-state">
          <NSpin size="small" />
          <span>正在加载 Skills</span>
        </div>
        <div v-else-if="skillsError" class="agent-skill-state agent-skill-error" role="alert">
          <span>{{ skillsError }}</span>
          <button type="button" :disabled="disabled" @click="refresh">重试</button>
        </div>
        <div v-else-if="filteredSkills.length === 0" class="agent-skill-state">
          {{ query ? '没有匹配的 Skill' : '当前主机没有可用 Skill' }}
        </div>
        <div v-for="skill in filteredSkills" v-else :key="skill.id" class="agent-skill-option">
          <NCheckbox
            :checked="selectedSkillIds.includes(skill.id)"
            :disabled="skillDisabled(skill.id)"
            @update:checked="updateSkill(skill.id, $event)"
          />
          <button
            type="button"
            class="agent-skill-copy"
            :disabled="skillDisabled(skill.id)"
            @click="store.toggleSkill(skill.id)"
          >
            <span class="agent-skill-name-row">
              <strong>{{ skill.name }}</strong>
              <small>{{ skill.source }}</small>
            </span>
            <span class="agent-skill-description">{{ skill.description }}</span>
          </button>
        </div>
      </div>
    </div>
  </NPopover>
</template>

<style>
.agent-skill-trigger {
  display: inline-flex;
  min-width: 0;
  height: 25px;
  flex: 0 1 auto;
  align-items: center;
  gap: 5px;
  padding: 0 7px;
  border: 0;
  border-radius: var(--app-radius-control);
  color: var(--agent-muted, #64748b);
  background: var(--agent-hover, rgba(100, 116, 139, 0.09));
  font-size: 9px;
  cursor: pointer;
}

.agent-skill-trigger span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.agent-skill-trigger strong {
  display: grid;
  min-width: 16px;
  height: 16px;
  place-items: center;
  padding: 0 4px;
  border-radius: 8px;
  color: white;
  background: var(--app-primary-color);
  font-size: 9px;
}

.agent-skill-trigger-active {
  color: var(--app-primary-color);
  background: var(--app-primary-soft);
}

.agent-skill-trigger:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-skill-picker {
  width: min(320px, calc(100vw - 24px));
  color: var(--n-text-color);
}

.agent-skill-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 9px;
}

.agent-skill-title {
  font-size: 12px;
  font-weight: 600;
}

.agent-skill-header-actions {
  display: flex;
  align-items: center;
  gap: 2px;
}

.agent-skill-refresh {
  display: grid;
  width: 27px;
  height: 27px;
  place-items: center;
  border: 0;
  border-radius: var(--app-radius-control);
  color: var(--n-text-color-3);
  background: transparent;
  cursor: pointer;
}

.agent-skill-refresh:hover:not(:disabled) {
  background: var(--n-color-embedded);
}

.agent-skill-refresh:disabled {
  opacity: 0.45;
}

.agent-skill-search {
  display: flex;
  height: 30px;
  align-items: center;
  gap: 7px;
  padding: 0 9px;
  border: 1px solid var(--n-border-color);
  border-radius: var(--app-radius-control);
  color: var(--n-text-color-3);
}

.agent-skill-search input {
  width: 100%;
  min-width: 0;
  border: 0;
  outline: 0;
  color: var(--n-text-color);
  background: transparent;
  font-size: 11px;
}

.agent-skill-list {
  max-height: min(320px, 50vh);
  margin: 9px -6px -5px;
  overflow-y: auto;
  padding: 0 6px 5px;
}

.agent-skill-option {
  display: flex;
  min-width: 0;
  align-items: flex-start;
  gap: 9px;
  padding: 8px;
  border-radius: var(--app-radius-item);
  cursor: pointer;
}

.agent-skill-option:hover {
  background: var(--n-color-embedded);
}

.agent-skill-option .n-checkbox {
  margin-top: 2px;
  flex: 0 0 auto;
}

.agent-skill-copy,
.agent-skill-name-row,
.agent-skill-description {
  display: block;
  min-width: 0;
}

.agent-skill-copy {
  flex: 1;
  padding: 0;
  border: 0;
  color: inherit;
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.agent-skill-copy:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.agent-skill-name-row {
  display: flex;
  align-items: center;
  gap: 7px;
}

.agent-skill-name-row strong {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 11px;
  font-weight: 600;
}

.agent-skill-name-row small {
  max-width: 42%;
  flex: 0 1 auto;
  overflow: hidden;
  padding: 1px 5px;
  border-radius: var(--app-radius-control);
  color: var(--n-text-color-3);
  background: var(--n-color-embedded);
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 9px;
}

.agent-skill-description {
  display: -webkit-box;
  margin-top: 3px;
  overflow: hidden;
  color: var(--n-text-color-3);
  overflow-wrap: anywhere;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  font-size: 10px;
  line-height: 1.45;
}

.agent-skill-state {
  display: flex;
  min-height: 92px;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 14px;
  color: var(--n-text-color-3);
  text-align: center;
  overflow-wrap: anywhere;
  font-size: 11px;
}

.agent-skill-error {
  flex-direction: column;
  color: #dc2626;
}

.agent-skill-error button {
  border: 0;
  color: var(--app-primary-color);
  background: transparent;
  cursor: pointer;
}

.agent-skill-spinning {
  animation: agent-skill-spin 0.8s linear infinite;
}

@keyframes agent-skill-spin {
  to {
    transform: rotate(360deg);
  }
}
</style>

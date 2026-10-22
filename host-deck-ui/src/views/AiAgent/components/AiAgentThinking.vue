<script setup lang="ts">
import { computed, ref } from 'vue'
import { ChevronRight, LoaderCircle } from '@lucide/vue'
import AiAgentMarkdown from './AiAgentMarkdown.vue'

const props = defineProps<{
  content: string
  running?: boolean
}>()
const emit = defineEmits<{ rendered: [] }>()

const expanded = ref<boolean | null>(null)
const open = computed(() => expanded.value ?? Boolean(props.running))
</script>

<template>
  <div v-if="content" class="agent-reasoning">
    <button
      type="button"
      class="agent-reasoning-toggle"
      :aria-expanded="open"
      @click="expanded = !open"
    >
      <LoaderCircle v-if="running" :size="13" class="agent-reasoning-spinner" />
      <ChevronRight v-else :size="13" :class="{ 'agent-reasoning-expanded': open }" />
      <span>{{ running ? '正在思考' : '思考过程' }}</span>
    </button>
    <div v-if="open" class="agent-reasoning-content">
      <AiAgentMarkdown :content="content" :streaming="running" @rendered="emit('rendered')" />
    </div>
  </div>
</template>

<style scoped>
.agent-reasoning {
  margin-bottom: 12px;
  color: var(--agent-muted);
}

.agent-reasoning-toggle {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 0;
  border: 0;
  color: inherit;
  background: transparent;
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}

.agent-reasoning-toggle:hover {
  color: var(--agent-text);
}

.agent-reasoning-toggle:focus-visible {
  outline: 2px solid var(--app-primary-color);
  outline-offset: 3px;
}

.agent-reasoning-expanded {
  transform: rotate(90deg);
}

.agent-reasoning-content {
  margin-top: 6px;
  padding-left: 14px;
  border-left: 2px solid var(--agent-border);
}

.agent-reasoning-spinner {
  animation: agent-reasoning-spin 1.2s linear infinite;
}

@keyframes agent-reasoning-spin {
  to {
    transform: rotate(360deg);
  }
}

@media (prefers-reduced-motion: reduce) {
  .agent-reasoning-spinner {
    animation: none;
  }
}
</style>

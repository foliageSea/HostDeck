import { defineComponent } from 'vue'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useAiAgentStore } from '@/stores/ai-agent'
import AiAgentSkillPicker from '../AiAgentSkillPicker.vue'

const apiMocks = vi.hoisted(() => ({
  listSkills: vi.fn(),
}))

vi.mock('@/api/ai-agent', () => ({ aiAgentApi: apiMocks }))

const PopoverStub = defineComponent({
  template: '<div><slot name="trigger" /><slot /></div>',
})

const CheckboxStub = defineComponent({
  props: { checked: Boolean, disabled: Boolean },
  emits: ['update:checked'],
  template:
    '<input type="checkbox" :checked="checked" :disabled="disabled" @change="$emit(\'update:checked\', $event.target.checked)" />',
})

function mountPicker(disabled = false) {
  return mount(AiAgentSkillPicker, {
    props: { connectionId: 'connection-1', disabled },
    global: {
      stubs: {
        NCheckbox: CheckboxStub,
        NPopover: PopoverStub,
        NSpin: { template: '<span class="spin" />' },
      },
    },
  })
}

describe('AiAgentSkillPicker', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
  })

  it('searches skills and supports multiple selections with source labels', async () => {
    const store = useAiAgentStore()
    store.skills = [
      {
        description: 'Inspect application logs',
        id: 'logs',
        name: 'Log review',
        source: 'workspace',
      },
      { description: 'Check service health', id: 'services', name: 'Services', source: 'builtin' },
    ]
    const wrapper = mountPicker()

    expect(wrapper.text()).toContain('workspace')
    expect(wrapper.text()).toContain('builtin')
    const checkboxes = wrapper.findAll('input[type="checkbox"]')
    await checkboxes[0]!.setValue(true)
    await wrapper.findAll('.agent-skill-copy')[1]!.trigger('click')
    expect(store.selectedSkillIds).toEqual(['logs', 'services'])
    expect(wrapper.get('.agent-skill-trigger').text()).toContain('2')

    await wrapper.get('input[type="search"]').setValue('health')
    expect(wrapper.text()).not.toContain('Log review')
    expect(wrapper.text()).toContain('Services')
  })

  it('shows loading, error, and empty states and disables selection while running', async () => {
    const store = useAiAgentStore()
    store.loadingSkills = true
    const wrapper = mountPicker(true)
    expect(wrapper.text()).toContain('正在加载 Skills')
    expect(wrapper.get('.agent-skill-trigger').attributes('disabled')).toBeDefined()

    store.loadingSkills = false
    store.skillsError = '技能加载失败'
    await wrapper.vm.$nextTick()
    expect(wrapper.get('[role="alert"]').text()).toContain('技能加载失败')

    store.skillsError = null
    await wrapper.vm.$nextTick()
    expect(wrapper.text()).toContain('当前主机没有可用 Skill')
  })
})

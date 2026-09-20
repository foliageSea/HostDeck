import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import AiAgentSkillSettings from '../AiAgentSkillSettings.vue'

const skillContent = '---\nname: logs\ndescription: Inspect logs\n---\n\n# Logs\n'
const skill = {
  content: skillContent,
  description: 'Inspect logs',
  editable: true,
  id: 'hostdeck:7',
  name: 'logs',
  source: 'hostdeck',
}

const apiMocks = vi.hoisted(() => ({
  createManagedSkill: vi.fn(),
  deleteManagedSkill: vi.fn(),
  getManagedSkill: vi.fn(),
  listManagedSkills: vi.fn(),
  updateManagedSkill: vi.fn(),
}))

const dialogOptions = vi.hoisted(() => ({ current: null as null | Record<string, unknown> }))
const uiMocks = vi.hoisted(() => ({
  dialog: {
    warning: vi.fn((options: Record<string, unknown>) => {
      dialogOptions.current = options
      return { loading: false }
    }),
  },
  message: { error: vi.fn(), success: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/api/ai-agent', () => ({ aiAgentApi: apiMocks }))
vi.mock('@/lib/ui', () => ({ getUiApi: () => uiMocks }))

function mountSettings() {
  return mount(AiAgentSkillSettings, {
    global: {
      stubs: {
        CodeEditor: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<textarea class="code-editor-stub" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
        },
        NButton: {
          props: ['loading'],
          emits: ['click'],
          template:
            '<button type="button" @click="$emit(\'click\')"><slot name="icon" /><slot /></button>',
        },
        NSpin: { template: '<span />' },
      },
    },
  })
}

describe('AiAgentSkillSettings', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
    dialogOptions.current = null
    apiMocks.listManagedSkills.mockResolvedValue([skill])
    apiMocks.getManagedSkill.mockResolvedValue(skill)
    apiMocks.createManagedSkill.mockResolvedValue(skill)
    apiMocks.updateManagedSkill.mockResolvedValue(skill)
    apiMocks.deleteManagedSkill.mockResolvedValue(undefined)
  })

  it('creates a skill from a valid SKILL.md template', async () => {
    const wrapper = mountSettings()
    await flushPromises()

    await wrapper
      .findAll('button')
      .find((button) => button.text() === '新建')!
      .trigger('click')
    const editor = wrapper.get('.code-editor-stub')
    expect((editor.element as HTMLTextAreaElement).value).toContain(
      '---\nname: new-skill\ndescription:',
    )
    await wrapper
      .findAll('button')
      .find((button) => button.text() === '保存')!
      .trigger('click')
    await flushPromises()

    expect(apiMocks.createManagedSkill).toHaveBeenCalledWith(
      expect.stringContaining('name: new-skill'),
    )
  })

  it('loads full content for editing and confirms deletion', async () => {
    const wrapper = mountSettings()
    await flushPromises()

    await wrapper.get('.agent-skill-library-copy').trigger('click')
    await flushPromises()
    expect(apiMocks.getManagedSkill).toHaveBeenCalledWith(7)
    expect((wrapper.get('.code-editor-stub').element as HTMLTextAreaElement).value).toBe(
      skillContent,
    )

    await wrapper.get('[aria-label="删除 logs"]').trigger('click')
    expect(uiMocks.dialog.warning).toHaveBeenCalledWith(
      expect.objectContaining({ title: '删除 Skill' }),
    )
    await (dialogOptions.current?.onPositiveClick as () => Promise<void>)()
    expect(apiMocks.deleteManagedSkill).toHaveBeenCalledWith(7)
  })
})

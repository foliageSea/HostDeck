import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import AiAgentToolList from '../AiAgentToolList.vue'

const apiMocks = vi.hoisted(() => ({
  listTools: vi.fn(),
}))
const uiMocks = vi.hoisted(() => ({
  message: { error: vi.fn() },
}))

vi.mock('@/api/ai-agent', () => ({ aiAgentApi: apiMocks }))
vi.mock('@/lib/ui', () => ({ getUiApi: () => uiMocks }))

describe('AiAgentToolList', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
    apiMocks.listTools.mockResolvedValue([
      {
        description: 'List files and subdirectories.',
        inputSchema: { properties: { path: { type: 'string' } }, type: 'object' },
        name: 'directory_list',
        requiresApproval: true,
        source: 'built-in',
      },
      {
        description: '[MCP: GitHub] Search repositories.',
        inputSchema: { properties: { query: { type: 'string' } }, type: 'object' },
        name: 'mcp_1_search',
        requiresApproval: true,
        source: 'mcp',
      },
    ])
  })

  it('loads and displays built-in and MCP tools with approval metadata', async () => {
    const wrapper = mount(AiAgentToolList, {
      props: { active: true },
      global: {
        stubs: {
          NButton: { template: '<button type="button"><slot name="icon" /><slot /></button>' },
          NInput: { props: ['clearable', 'size', 'value'], template: '<input />' },
          NSpin: { template: '<span />' },
        },
      },
    })
    await flushPromises()

    expect(apiMocks.listTools).toHaveBeenCalledOnce()
    expect(wrapper.text()).toContain('内置 1')
    expect(wrapper.text()).toContain('MCP 1')
    expect(wrapper.text()).toContain('浏览目录')
    expect(wrapper.text()).toContain('mcp_1_search')
    expect(wrapper.text()).toContain('执行前需批准')
    expect(wrapper.text()).toContain('path')
    expect(wrapper.text()).toContain('query')
  })
})

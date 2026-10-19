import { mount } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import AiAgentMarkdown from '../AiAgentMarkdown.vue'

const uiMocks = vi.hoisted(() => ({
  error: vi.fn(),
  success: vi.fn(),
}))

vi.mock('@/lib/ui', () => ({
  getUiApi: () => ({ message: uiMocks }),
}))

function render(content: string) {
  return mount(AiAgentMarkdown, { props: { content } })
}

describe('AiAgentMarkdown', () => {
  it('renders common markdown structures', () => {
    const wrapper = render('**bold** and `code`\n\n- one\n- two\n\n| a | b |\n| - | - |\n| 1 | 2 |')

    expect(wrapper.find('strong').text()).toBe('bold')
    expect(wrapper.findAll('li')).toHaveLength(2)
    expect(wrapper.find('table').exists()).toBe(true)
  })

  it('adds a copy button to fenced code blocks', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText },
    })

    const wrapper = render('Use `inline code` here.\n\n```bash\nsudo passwd root\n```')
    const button = wrapper.get('.agent-code-copy')

    expect(wrapper.findAll('.agent-code-copy')).toHaveLength(1)
    expect(button.attributes('aria-label')).toBe('复制代码')
    expect(wrapper.get('pre code').text()).toBe('sudo passwd root')

    const multilineWrapper = render('```text\nline one\nline two\n```')
    expect(multilineWrapper.get('pre code').element.textContent).toBe('line one\nline two\n')

    await button.trigger('click')

    expect(writeText).toHaveBeenCalledWith('sudo passwd root')
    expect(uiMocks.success).toHaveBeenCalledWith('代码已复制。')
  })

  it('sanitizes scripts, event handlers, and unsafe attributes', () => {
    const wrapper = render(
      '<script>window.__pwned = true</script>\n\n<img src=x onerror="window.__pwned = true">',
    )

    expect(wrapper.find('script').exists()).toBe(false)
    expect(wrapper.html()).not.toContain('onerror')
    expect((window as unknown as Record<string, unknown>).__pwned).toBeUndefined()
  })

  it('opens links safely in a new tab', () => {
    const wrapper = render('[docs](https://example.test/docs)')
    const link = wrapper.get('a')

    expect(link.attributes('href')).toBe('https://example.test/docs')
    expect(link.attributes('target')).toBe('_blank')
    expect(link.attributes('rel')).toContain('noopener')
  })
})

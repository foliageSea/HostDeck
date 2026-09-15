import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import AiAgentMarkdown from '../AiAgentMarkdown.vue'

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

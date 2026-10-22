import { nextTick } from 'vue'
import { mount } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import { marked } from 'marked'
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
  it('batches streamed fragments and flushes the final text with highlighting immediately', async () => {
    vi.useFakeTimers()
    const parse = vi.spyOn(marked, 'parse')
    const wrapper = mount(AiAgentMarkdown, { props: { content: '```js\nconst ', streaming: true } })
    try {
      parse.mockClear()
      for (let i = 1; i <= 100; i++) {
        await wrapper.setProps({ content: `\`\`\`js\nconst answer = ${i};\n\`\`\`` })
      }
      expect(parse).not.toHaveBeenCalled()
      await vi.advanceTimersByTimeAsync(50)
      expect(parse).toHaveBeenCalledTimes(1)
      expect(wrapper.get('pre code').text()).toContain('answer = 100')
      expect(wrapper.find('.agent-code-copy').exists()).toBe(false)
      expect(wrapper.find('.hljs-keyword').exists()).toBe(false)

      await wrapper.setProps({ content: '```js\nconst answer = 101;\n```' })
      await wrapper.setProps({ streaming: false })
      await nextTick()
      expect(wrapper.get('pre code .hljs-number').text()).toBe('101')
      expect(wrapper.findAll('.agent-code-copy')).toHaveLength(1)
      const calls = parse.mock.calls.length
      await vi.advanceTimersByTimeAsync(100)
      expect(parse).toHaveBeenCalledTimes(calls)
    } finally {
      wrapper.unmount()
      parse.mockRestore()
      vi.useRealTimers()
    }
  })

  it('cancels pending stream rendering when unmounted', async () => {
    vi.useFakeTimers()
    const wrapper = mount(AiAgentMarkdown, { props: { content: 'First', streaming: true } })
    try {
      await wrapper.setProps({ content: 'First second' })
      wrapper.unmount()
      expect(vi.getTimerCount()).toBe(0)
    } finally {
      vi.useRealTimers()
    }
  })

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
    expect(wrapper.get('.agent-code-line-numbers').text()).toBe('1')
    expect(wrapper.findAll('.agent-code-line-numbers')).toHaveLength(1)
    expect(wrapper.get('.agent-code-line-numbers').attributes('aria-hidden')).toBe('true')

    const multilineWrapper = render('```text\nline one\n\nline three\n```')
    expect(multilineWrapper.get('pre code').element.textContent).toBe('line one\n\nline three\n')
    expect(multilineWrapper.get('.agent-code-line-numbers').text()).toBe('1\n2\n3')

    await button.trigger('click')

    expect(writeText).toHaveBeenCalledWith('sudo passwd root')
    expect(uiMocks.success).toHaveBeenCalledWith('代码已复制。')

    await multilineWrapper.get('.agent-code-copy').trigger('click')
    expect(writeText).toHaveBeenLastCalledWith('line one\n\nline three\n')

    await multilineWrapper.setProps({ content: '```text\nline one\n\nline three\nline four\n```' })
    await nextTick()
    expect(multilineWrapper.get('.agent-code-line-numbers').text()).toBe('1\n2\n3\n4')
    expect(multilineWrapper.findAll('.agent-code-copy')).toHaveLength(1)
  })

  it('highlights code without changing its text, line numbers, or clipboard content', async () => {
    const source = 'const html = "<img src=x onerror=alert(1)>";\nconsole.log(html);\n'
    const writeText = vi.fn().mockResolvedValue(undefined)
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText },
    })
    const wrapper = render('```js\n' + source + '```')

    expect(wrapper.get('pre code').element.textContent).toBe(source)
    expect(wrapper.get('pre code .hljs-keyword').text()).toBe('const')
    expect(wrapper.get('pre code .hljs-string').text()).toContain('<img')
    expect(wrapper.find('img').exists()).toBe(false)
    expect(wrapper.get('.agent-code-line-numbers').text()).toBe('1\n2')

    await wrapper.get('.agent-code-copy').trigger('click')
    expect(writeText).toHaveBeenCalledWith(source)

    await wrapper.setProps({ content: '```js\nconst answer = 42;\n```' })
    await nextTick()
    expect(wrapper.get('pre code .hljs-number').text()).toBe('42')
    expect(wrapper.get('.agent-code-line-numbers').text()).toBe('1')
    expect(wrapper.findAll('.agent-code-copy')).toHaveLength(1)
  })

  it.each([
    ['sh', 'echo "$HOME"'],
    ['shell', 'echo "$HOME"'],
    ['json', '{"answer": 42}'],
    ['python', 'def hello():\n    return "world"'],
    ['dart', 'final answer = 42;'],
    ['dockerfile', 'FROM node:22'],
    ['ps1', 'Write-Host "hello"'],
    ['nginx', 'server { listen 80; }'],
    ['vue', '<template><p>Hello</p></template>'],
  ])('highlights %s code blocks', (language, source) => {
    const wrapper = render('```' + language + '\n' + source + '\n```')

    expect(wrapper.find('pre code span[class^="hljs-"]').exists()).toBe(true)
    expect(wrapper.get('pre code').element.textContent?.trimEnd()).toBe(source)
  })

  it.each(['text', 'unknown-language'])('keeps %s blocks as plain text', (language) => {
    const source = 'const html = "<script>alert(1)</script>";'
    const wrapper = render('```' + language + '\n' + source + '\n```')

    expect(wrapper.find('pre code span').exists()).toBe(false)
    expect(wrapper.find('script').exists()).toBe(false)
    expect(wrapper.get('pre code').text()).toBe(source)
  })

  it('detects syntax for code blocks without a language', () => {
    const wrapper = render('```\nconst answer = 42;\nconsole.log(answer);\n```')

    expect(wrapper.find('pre code .hljs-keyword').exists()).toBe(true)
    expect(wrapper.get('pre code').element.textContent).toBe(
      'const answer = 42;\nconsole.log(answer);\n',
    )
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

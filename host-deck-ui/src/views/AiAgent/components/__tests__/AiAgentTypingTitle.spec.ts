import { mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import AiAgentTypingTitle from '../AiAgentTypingTitle.vue'

const TITLE = '我们要维护什么？'
const OTHER_TITLE = '今天想聊些什么？'
const DELAY = 260
const SPEED = 90
const HOLD = 2400

function mountTitle(props: { text?: string; speed?: number; delay?: number } = {}) {
  return mount(AiAgentTypingTitle, { props: { text: TITLE, ...props } })
}

function typed(wrapper: ReturnType<typeof mountTitle>) {
  return wrapper.get('.agent-typing-text').text()
}

describe('AiAgentTypingTitle', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
    delete (window as unknown as Record<string, unknown>).matchMedia
  })

  it('types the heading, holds it, then loops', async () => {
    const wrapper = mountTitle()
    await wrapper.vm.$nextTick()
    expect(wrapper.get('h1').attributes('aria-label')).toBe(TITLE)
    expect(typed(wrapper)).toBe('')
    expect(wrapper.find('.agent-typing-caret').exists()).toBe(true)

    await vi.advanceTimersByTimeAsync(DELAY)
    expect(typed(wrapper)).toBe('我')

    await vi.advanceTimersByTimeAsync(SPEED * (TITLE.length - 1))
    expect(typed(wrapper)).toBe(TITLE)
    expect(wrapper.find('.agent-typing-caret').exists()).toBe(true)

    await vi.advanceTimersByTimeAsync(HOLD)
    expect(typed(wrapper)).toBe('')
    expect(wrapper.find('.agent-typing-caret').exists()).toBe(true)

    await vi.advanceTimersByTimeAsync(DELAY)
    expect(typed(wrapper)).toBe('我')
    wrapper.unmount()
  })

  it('restarts typing when the heading text changes', async () => {
    const wrapper = mountTitle({ text: OTHER_TITLE })
    await vi.advanceTimersByTimeAsync(DELAY + SPEED * 3)
    expect(typed(wrapper)).toBe('今天想聊')

    await wrapper.setProps({ text: TITLE })
    await vi.advanceTimersByTimeAsync(0)
    expect(typed(wrapper)).toBe('')

    await vi.advanceTimersByTimeAsync(DELAY + SPEED * TITLE.length)
    expect(typed(wrapper)).toBe(TITLE)
    wrapper.unmount()
  })

  it('shows the whole heading at once when reduced motion is preferred', async () => {
    Object.defineProperty(window, 'matchMedia', {
      configurable: true,
      value: vi.fn().mockReturnValue({ matches: true, media: '(prefers-reduced-motion: reduce)' }),
    })

    const wrapper = mountTitle()
    await wrapper.vm.$nextTick()
    expect(typed(wrapper)).toBe(TITLE)
    expect(wrapper.find('.agent-typing-caret').exists()).toBe(false)
    wrapper.unmount()
  })

  it('does not leave timers behind after unmount', async () => {
    const wrapper = mountTitle()
    await vi.advanceTimersByTimeAsync(DELAY)
    wrapper.unmount()
    expect(vi.getTimerCount()).toBe(0)
  })
})

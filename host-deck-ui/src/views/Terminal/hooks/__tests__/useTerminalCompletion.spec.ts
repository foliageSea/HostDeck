import { flushPromises } from '@vue/test-utils'
import { shallowRef } from 'vue'
import type { Terminal } from '@xterm/xterm'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { terminalApi } from '@/api/terminal'
import { useTerminalCompletion } from '../useTerminalCompletion'

vi.mock('@/api/terminal', () => ({
  terminalApi: {
    listSnippets: vi.fn(),
  },
}))

function createCompletion() {
  const focus = vi.fn()
  let bufferType: 'normal' | 'alternate' = 'normal'
  const textarea = document.createElement('textarea')
  textarea.getBoundingClientRect = () => new DOMRect(100, 120, 1, 20)
  const terminal = shallowRef({
    buffer: {
      active: {
        get type() {
          return bufferType
        },
      },
    },
    focus,
    textarea,
  } as unknown as Terminal)
  const sent: string[] = []
  const completion = useTerminalCompletion({
    sendInput: (data) => {
      sent.push(data)
      completion.handleData(data)
      return true
    },
    terminal,
  })

  return {
    completion,
    focus,
    sent,
    setBufferType: (value: 'normal' | 'alternate') => {
      bufferType = value
    },
  }
}

describe('useTerminalCompletion', () => {
  beforeEach(() => {
    vi.mocked(terminalApi.listSnippets).mockReset()
    vi.mocked(terminalApi.listSnippets).mockResolvedValue([])
  })

  it('loads snippets and sends only the missing suffix when accepted', async () => {
    vi.mocked(terminalApi.listSnippets).mockResolvedValue([
      {
        command: 'docker logs --follow api',
        createdAt: 1,
        id: 1,
        name: 'API logs',
        updatedAt: 1,
      },
    ])
    const { completion, focus, sent } = createCompletion()

    await completion.refreshSnippets()
    completion.handleData('docker l')
    await flushPromises()
    expect(completion.items.value[0]?.source).toBe('snippet')

    expect(completion.accept()).toBe(true)
    expect(sent).toEqual(['ogs --follow api'])
    expect(focus).toHaveBeenCalled()
    expect(completion.visible.value).toBe(false)
  })

  it('accepts and executes with Enter while intercepting the key event', () => {
    const { completion, sent } = createCompletion()
    completion.handleData('git st')
    const event = new KeyboardEvent('keydown', { cancelable: true, key: 'Enter' })
    const stopPropagation = vi.spyOn(event, 'stopPropagation')

    expect(completion.handleKeyEvent(event)).toBe(true)
    expect(sent).toEqual(['atus', '\r'])
    expect(event.defaultPrevented).toBe(true)
    expect(stopPropagation).toHaveBeenCalled()
  })

  it('does not intercept keys when no candidates are visible', () => {
    const { completion, sent } = createCompletion()
    const event = new KeyboardEvent('keydown', { key: 'Tab' })

    expect(completion.handleKeyEvent(event)).toBe(false)
    expect(sent).toEqual([])
  })

  it('cycles candidates and closes them on Escape', () => {
    const { completion } = createCompletion()
    completion.handleData('git')
    const initialIndex = completion.activeIndex.value

    completion.handleKeyEvent(new KeyboardEvent('keydown', { key: 'ArrowDown' }))
    expect(completion.activeIndex.value).not.toBe(initialIndex)

    completion.handleKeyEvent(new KeyboardEvent('keydown', { key: 'Escape' }))
    expect(completion.visible.value).toBe(false)
  })

  it('suppresses completion in alternate buffers and sensitive prompts', () => {
    const { completion, setBufferType } = createCompletion()
    setBufferType('alternate')
    completion.handleData('git')
    expect(completion.visible.value).toBe(false)

    setBufferType('normal')
    completion.reset()
    completion.handleOutput('\u001b[31mPassword:\u001b[0m ')
    completion.handleData('secret')
    expect(completion.visible.value).toBe(false)
  })

  it('positions the popup within the viewport', () => {
    const { completion } = createCompletion()
    completion.updateAnchor()

    expect(completion.anchorStyle.value).toEqual({ left: '100px', top: '148px' })
  })
})

import { describe, expect, it } from 'vitest'
import {
  createDefaultWindowSwitchShortcut,
  createDefaultWindowSwitcherToggleShortcut,
  createKeyboardShortcut,
  formatKeyboardShortcut,
  matchesKeyboardShortcut,
} from '@/lib/keyboard-shortcut'

describe('keyboard shortcuts', () => {
  it('uses Shift only for toggling the window switcher', () => {
    expect(createDefaultWindowSwitchShortcut().shiftKey).toBe(false)
    expect(createDefaultWindowSwitcherToggleShortcut().shiftKey).toBe(true)
  })

  it('creates and formats a modified shortcut', () => {
    const event = new KeyboardEvent('keydown', {
      code: 'KeyK',
      ctrlKey: true,
      key: 'k',
      shiftKey: true,
    })

    const shortcut = createKeyboardShortcut(event)

    expect(shortcut).not.toBeNull()
    expect(formatKeyboardShortcut(shortcut!)).toBe('Ctrl + Shift + K')
    expect(matchesKeyboardShortcut(event, shortcut!)).toBe(true)
  })

  it('rejects unmodified and modifier-only keys', () => {
    expect(
      createKeyboardShortcut(new KeyboardEvent('keydown', { code: 'KeyK', key: 'k' })),
    ).toBeNull()
    expect(
      createKeyboardShortcut(
        new KeyboardEvent('keydown', { code: 'ControlLeft', ctrlKey: true, key: 'Control' }),
      ),
    ).toBeNull()
  })
})

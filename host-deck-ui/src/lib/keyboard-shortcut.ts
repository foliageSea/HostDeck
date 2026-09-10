export interface KeyboardShortcut {
  altKey: boolean
  code: string
  ctrlKey: boolean
  ctrlOrMeta: boolean
  key: string
  metaKey: boolean
  shiftKey: boolean
}

const MODIFIER_CODES = new Set([
  'AltLeft',
  'AltRight',
  'ControlLeft',
  'ControlRight',
  'MetaLeft',
  'MetaRight',
  'ShiftLeft',
  'ShiftRight',
])

export function isMacPlatform() {
  return navigator.platform.startsWith('Mac') || navigator.userAgent.includes('Macintosh')
}

export function createDefaultWindowSwitchShortcut(): KeyboardShortcut {
  return {
    altKey: !isMacPlatform(),
    code: 'Backquote',
    ctrlKey: false,
    ctrlOrMeta: isMacPlatform(),
    key: '`',
    metaKey: false,
    shiftKey: false,
  }
}

export function createDefaultWindowSwitcherToggleShortcut(): KeyboardShortcut {
  return {
    ...createDefaultWindowSwitchShortcut(),
    shiftKey: true,
  }
}

export function normalizeKeyboardShortcut(
  value: unknown,
  defaultShortcut = createDefaultWindowSwitchShortcut(),
): KeyboardShortcut {
  if (!value || typeof value !== 'object') {
    return defaultShortcut
  }

  const candidate = value as Partial<KeyboardShortcut>
  if (typeof candidate.code !== 'string' || !candidate.code || MODIFIER_CODES.has(candidate.code)) {
    return defaultShortcut
  }

  const shortcut = {
    altKey: candidate.altKey === true,
    code: candidate.code,
    ctrlKey: candidate.ctrlKey === true,
    ctrlOrMeta: candidate.ctrlOrMeta === true,
    key: typeof candidate.key === 'string' && candidate.key ? candidate.key : candidate.code,
    metaKey: candidate.metaKey === true,
    shiftKey: candidate.shiftKey === true,
  }

  return shortcut.altKey || shortcut.ctrlKey || shortcut.ctrlOrMeta || shortcut.metaKey
    ? shortcut
    : defaultShortcut
}

export function createKeyboardShortcut(event: KeyboardEvent): KeyboardShortcut | null {
  if (
    !event.code ||
    MODIFIER_CODES.has(event.code) ||
    (!event.altKey && !event.ctrlKey && !event.metaKey)
  ) {
    return null
  }

  return {
    altKey: event.altKey,
    code: event.code,
    ctrlKey: event.ctrlKey,
    ctrlOrMeta: false,
    key: event.key,
    metaKey: event.metaKey,
    shiftKey: event.shiftKey,
  }
}

export function matchesKeyboardShortcut(event: KeyboardEvent, shortcut: KeyboardShortcut) {
  const matchesPrimaryModifier = shortcut.ctrlOrMeta
    ? (event.ctrlKey || event.metaKey) && !(event.ctrlKey && event.metaKey)
    : event.ctrlKey === shortcut.ctrlKey && event.metaKey === shortcut.metaKey

  return (
    event.code === shortcut.code &&
    event.altKey === shortcut.altKey &&
    event.shiftKey === shortcut.shiftKey &&
    matchesPrimaryModifier
  )
}

export function formatKeyboardShortcut(shortcut: KeyboardShortcut) {
  const keys: string[] = []
  if (shortcut.ctrlOrMeta) {
    keys.push('Command / Control')
  } else {
    if (shortcut.ctrlKey) keys.push('Ctrl')
    if (shortcut.metaKey) keys.push(isMacPlatform() ? 'Command' : 'Meta')
  }
  if (shortcut.altKey) keys.push(isMacPlatform() ? 'Option' : 'Alt')
  if (shortcut.shiftKey) keys.push('Shift')

  const keyLabels: Record<string, string> = {
    ' ': 'Space',
    ArrowDown: '↓',
    ArrowLeft: '←',
    ArrowRight: '→',
    ArrowUp: '↑',
    Escape: 'Esc',
  }
  const key =
    keyLabels[shortcut.key] ??
    (shortcut.key.length === 1 ? shortcut.key.toUpperCase() : shortcut.key)
  keys.push(key)
  return keys.join(' + ')
}

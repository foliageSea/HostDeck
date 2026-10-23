import type { CSSProperties } from 'vue'

/**
 * ANSI（SGR）转义序列解析。容器日志里常见的 \u001b[32m 之类颜色码如果直接丢进 <pre>，
 * 会显示成 "[32m" 这样的乱码，这里把它们解析成可渲染的样式分段。
 */

export interface AnsiPalette {
  /** 0-7 普通色，8-15 高亮色 */
  colors: string[]
  foreground: string
  background: string
}

interface AnsiStyle {
  color?: string
  backgroundColor?: string
  fontWeight?: string
  fontStyle?: string
  textDecoration?: string
  opacity?: string
}

export interface AnsiSpan {
  text: string
  /** 可直接绑定到 :style */
  style: CSSProperties
}

export const darkAnsiPalette: AnsiPalette = {
  colors: [
    '#64748b',
    '#e06c75',
    '#98c379',
    '#e5c07b',
    '#61afef',
    '#c678dd',
    '#56b6c2',
    '#dbeafe',
    '#94a3b8',
    '#ff7b86',
    '#b5e890',
    '#ffd68a',
    '#82c4ff',
    '#e0a1f0',
    '#7fd6e0',
    '#f8fafc',
  ],
  foreground: '#dbeafe',
  background: 'rgba(2,6,23,0.9)',
}

export const lightAnsiPalette: AnsiPalette = {
  colors: [
    '#334155',
    '#b91c1c',
    '#15803d',
    '#a16207',
    '#1d4ed8',
    '#a21caf',
    '#0e7490',
    '#475569',
    '#64748b',
    '#dc2626',
    '#16a34a',
    '#ca8a04',
    '#2563eb',
    '#c026d3',
    '#0891b2',
    '#1e293b',
  ],
  foreground: 'rgba(30,41,59,0.96)',
  background: 'rgba(248,250,252,0.96)',
}

function cloneStyle(style: AnsiStyle): AnsiStyle {
  return { ...style }
}

function clearStyle(style: AnsiStyle) {
  for (const key of Object.keys(style)) delete style[key as keyof AnsiStyle]
}

function color256(index: number, palette: AnsiPalette): string | undefined {
  if (!Number.isFinite(index) || index < 0) return undefined
  if (index < 16) return palette.colors[index]
  if (index < 232) {
    const offset = index - 16
    const channels = [Math.floor(offset / 36), Math.floor((offset % 36) / 6), offset % 6]
    const level = (value: number) => (value === 0 ? 0 : 55 + value * 40)
    return `rgb(${level(channels[0])}, ${level(channels[1])}, ${level(channels[2])})`
  }
  if (index < 256) {
    const gray = 8 + (index - 232) * 10
    return `rgb(${gray}, ${gray}, ${gray})`
  }
  return undefined
}

function applySgr(style: AnsiStyle, paramsText: string, palette: AnsiPalette) {
  const params =
    paramsText === '' ? [0] : paramsText.split(';').map((item) => Number.parseInt(item, 10))
  for (let index = 0; index < params.length; index += 1) {
    const code = Number.isNaN(params[index]) ? 0 : params[index]
    if (code === 0) {
      clearStyle(style)
    } else if (code === 1) {
      style.fontWeight = '600'
    } else if (code === 2) {
      style.opacity = '0.7'
    } else if (code === 3) {
      style.fontStyle = 'italic'
    } else if (code === 4) {
      style.textDecoration = 'underline'
    } else if (code === 7) {
      const color = style.color ?? palette.foreground
      const background = style.backgroundColor ?? palette.background
      style.color = background
      style.backgroundColor = color
    } else if (code === 9) {
      style.textDecoration = 'line-through'
    } else if (code === 22) {
      delete style.fontWeight
      delete style.opacity
    } else if (code === 23) {
      delete style.fontStyle
    } else if (code === 24 || code === 29) {
      delete style.textDecoration
    } else if (code === 27) {
      delete style.color
      delete style.backgroundColor
    } else if (code >= 30 && code <= 37) {
      style.color = palette.colors[code - 30]
    } else if (code === 39) {
      delete style.color
    } else if (code >= 40 && code <= 47) {
      style.backgroundColor = palette.colors[code - 40]
    } else if (code === 49) {
      delete style.backgroundColor
    } else if (code >= 90 && code <= 97) {
      style.color = palette.colors[code - 90 + 8]
    } else if (code >= 100 && code <= 107) {
      style.backgroundColor = palette.colors[code - 100 + 8]
    } else if (code === 38 || code === 48) {
      const mode = params[index + 1]
      const target = (value: string | undefined) => {
        if (value === undefined) return
        if (code === 38) style.color = value
        else style.backgroundColor = value
      }
      if (mode === 5) {
        target(color256(params[index + 2], palette))
        index += 2
      } else if (mode === 2) {
        const [red, green, blue] = [params[index + 2], params[index + 3], params[index + 4]]
        if (
          [red, green, blue].every((value) => typeof value === 'number' && !Number.isNaN(value))
        ) {
          target(`rgb(${red}, ${green}, ${blue})`)
        }
        index += 4
      }
    }
  }
}

/** 读取从 start 开始的转义序列，返回结束位置和 SGR 参数（不是 SGR 时为 undefined）。 */
function readEscape(text: string, start: number): { end: number; sgr?: string } {
  const next = text[start + 1]
  if (next === '[') {
    let cursor = start + 2
    while (cursor < text.length) {
      const code = text.charCodeAt(cursor)
      if (code >= 0x40 && code <= 0x7e) {
        const params = text.slice(start + 2, cursor)
        return { end: cursor + 1, sgr: text[cursor] === 'm' ? params : undefined }
      }
      cursor += 1
    }
    return { end: text.length }
  }
  if (next === ']') {
    let cursor = start + 2
    while (cursor < text.length) {
      if (text[cursor] === '\u0007') return { end: cursor + 1 }
      if (text[cursor] === '\u001b' && text[cursor + 1] === '\\') return { end: cursor + 2 }
      cursor += 1
    }
    return { end: text.length }
  }
  // 两字节 / 三字节转义（如 \u001b(B）一律丢弃
  const skip = next === '(' || next === ')' || next === '#' ? 3 : 2
  return { end: Math.min(start + skip, text.length) }
}

function isSameStyle(left: AnsiStyle, right: AnsiStyle): boolean {
  const keys = new Set([...Object.keys(left), ...Object.keys(right)])
  for (const key of keys) {
    if (left[key as keyof AnsiStyle] !== right[key as keyof AnsiStyle]) return false
  }
  return true
}

/** 按 ANSI 颜色码切分为可渲染的样式分段；无法识别的转义序列会被丢弃。 */
export function parseAnsi(text: string, palette: AnsiPalette = darkAnsiPalette): AnsiSpan[] {
  const spans: AnsiSpan[] = []
  const style: AnsiStyle = {}
  let buffer = ''
  let cursor = 0

  const flush = () => {
    if (!buffer) return
    const snapshot = cloneStyle(style)
    const previous = spans[spans.length - 1]
    if (previous && isSameStyle(previous.style as AnsiStyle, snapshot)) previous.text += buffer
    else spans.push({ text: buffer, style: snapshot as CSSProperties })
    buffer = ''
  }

  while (cursor < text.length) {
    const char = text[cursor]
    if (char !== '\u001b') {
      buffer += char
      cursor += 1
      continue
    }
    const escape = readEscape(text, cursor)
    if (escape.sgr !== undefined) {
      flush()
      applySgr(style, escape.sgr, palette)
    }
    cursor = escape.end
  }
  flush()
  return spans
}

/** 去掉所有 ANSI 转义序列，用于复制、下载和关键字匹配。 */
export function stripAnsi(text: string): string {
  let output = ''
  let cursor = 0
  while (cursor < text.length) {
    const char = text[cursor]
    if (char !== '\u001b') {
      output += char
      cursor += 1
      continue
    }
    cursor = readEscape(text, cursor).end
  }
  return output
}

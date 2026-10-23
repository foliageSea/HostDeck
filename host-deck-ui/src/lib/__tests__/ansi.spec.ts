import { describe, expect, it } from 'vitest'
import { darkAnsiPalette, lightAnsiPalette, parseAnsi, stripAnsi } from '@/lib/ansi'

describe('stripAnsi', () => {
  it('removes SGR colour codes', () => {
    expect(stripAnsi('\u001b[32m[INFO]\u001b[0m started')).toBe('[INFO] started')
  })

  it('removes cursor and OSC sequences', () => {
    expect(stripAnsi('a\u001b[2Kb\u001b]0;title\u0007c')).toBe('abc')
  })

  it('drops an unterminated escape sequence', () => {
    expect(stripAnsi('ok\u001b[32')).toBe('ok')
  })

  it('keeps plain text untouched', () => {
    expect(stripAnsi('2026-10-23T01:37:28 [CORE] ready')).toBe('2026-10-23T01:37:28 [CORE] ready')
  })
})

describe('parseAnsi', () => {
  it('splits coloured spans and resets back to default', () => {
    const spans = parseAnsi('\u001b[32mOK\u001b[0m done')
    expect(spans).toEqual([
      { text: 'OK', style: { color: darkAnsiPalette.colors[2] } },
      { text: ' done', style: {} },
    ])
  })

  it('merges adjacent spans with identical style', () => {
    const spans = parseAnsi('\u001b[31ma\u001b[31mb')
    expect(spans).toEqual([{ text: 'ab', style: { color: darkAnsiPalette.colors[1] } }])
  })

  it('handles bold, underline and dim attributes', () => {
    const spans = parseAnsi('\u001b[1;4;2mX\u001b[22;24mY')
    expect(spans[0]).toEqual({
      text: 'X',
      style: { fontWeight: '600', textDecoration: 'underline', opacity: '0.7' },
    })
    expect(spans[1]).toEqual({ text: 'Y', style: {} })
  })

  it('resolves 256-colour and truecolor values', () => {
    const spans = parseAnsi('\u001b[38;5;196mA\u001b[38;2;1;2;3mB')
    expect(spans[0].style.color).toBe('rgb(255, 0, 0)')
    expect(spans[1].style.color).toBe('rgb(1, 2, 3)')
  })

  it('supports background colours and reverse video', () => {
    const spans = parseAnsi('\u001b[44mX\u001b[7mY')
    expect(spans[0]).toEqual({ text: 'X', style: { backgroundColor: darkAnsiPalette.colors[4] } })
    expect(spans[1]).toEqual({
      text: 'Y',
      style: {
        color: darkAnsiPalette.colors[4],
        backgroundColor: darkAnsiPalette.foreground,
      },
    })
  })

  it('uses the light palette when provided', () => {
    const spans = parseAnsi('\u001b[31mERR', lightAnsiPalette)
    expect(spans[0].style.color).toBe(lightAnsiPalette.colors[1])
  })

  it('drops non-SGR escape sequences without leaving residue', () => {
    const spans = parseAnsi('a\u001b[1Bb\u001b]8;;https://x\u0007c')
    expect(spans).toEqual([{ text: 'abc', style: {} }])
  })
})

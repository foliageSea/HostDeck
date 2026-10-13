import { describe, expect, it } from 'vitest'
import { createPinyinSearchIndex, matchesPinyinSearch } from '../app-search'

describe('pinyin application search', () => {
  const files = createPinyinSearchIndex('文件管理')

  it('indexes full pinyin and initials without tones', () => {
    expect(files).toEqual({ full: 'wenjianguanli', initials: 'wjgl' })
  })

  it.each([
    'wenjianguanli',
    'wenjian',
    'guanli',
    'WEN JIAN GUAN LI',
    'ｗｊｇｌ',
    'wjgl',
    'jgl',
    'wgl',
    'wl',
    '',
  ])('matches full, partial or fuzzy initials: %s', (query) => {
    expect(matchesPinyinSearch(files, query)).toBe(true)
  })

  it.each(['glwj', 'wjjgl', 'missing', '文件', 'wg-l'])(
    'does not match unrelated or out-of-order initials: %s',
    (query) => {
      expect(matchesPinyinSearch(files, query)).toBe(false)
    },
  )

  it('keeps Latin names and mixed Chinese/Latin names searchable', () => {
    const terminal = createPinyinSearchIndex('SSH 终端')
    expect(terminal).toEqual({ full: 'sshzhongduan', initials: 'sshzd' })
    expect(matchesPinyinSearch(terminal, 'SSH ZD')).toBe(true)
    expect(matchesPinyinSearch(terminal, 'sshzhongduan')).toBe(true)
    expect(matchesPinyinSearch(createPinyinSearchIndex('Terminal'), 'TERMINAL')).toBe(true)
  })

  it('uses phrase pronunciations for polyphonic words', () => {
    const index = createPinyinSearchIndex('重庆连接')
    expect(index.initials).toBe('cqlj')
    expect(matchesPinyinSearch(index, 'chongqing')).toBe(true)
    expect(matchesPinyinSearch(index, 'cqlj')).toBe(true)
  })

  it('accepts v or ü for umlaut pinyin', () => {
    const index = createPinyinSearchIndex('吕布笔记')
    expect(matchesPinyinSearch(index, 'lvbu')).toBe(true)
    expect(matchesPinyinSearch(index, 'lübu')).toBe(true)
  })
})

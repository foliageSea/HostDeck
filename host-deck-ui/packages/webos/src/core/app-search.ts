import { pinyin } from 'pinyin-pro'

export interface PinyinSearchIndex {
  full: string
  initials: string
}

function normalize(value: string) {
  return value.normalize('NFKC').toLocaleLowerCase().replace(/\s+/gu, '')
}

export function createPinyinSearchIndex(title: string): PinyinSearchIndex {
  const words = pinyin(title, { type: 'all', toneType: 'none', nonZh: 'consecutive', v: true })
  return {
    full: normalize(words.map((word) => (word.isZh ? word.pinyin : word.origin)).join('')),
    initials: normalize(words.map((word) => word.first).join('')),
  }
}

export function matchesPinyinSearch(index: PinyinSearchIndex, query: string) {
  const normalized = normalize(query).replaceAll('ü', 'v')
  if (!normalized) return true
  if (index.full.includes(normalized) || index.initials.includes(normalized)) return true
  if (!/^[a-z\d]+$/.test(normalized)) return false

  let position = 0
  for (const letter of index.initials) {
    if (letter === normalized[position]) position++
    if (position === normalized.length) return true
  }
  return false
}

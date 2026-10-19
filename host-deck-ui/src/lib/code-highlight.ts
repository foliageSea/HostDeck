import hljs from 'highlight.js/lib/common'
import dart from 'highlight.js/lib/languages/dart'
import dockerfile from 'highlight.js/lib/languages/dockerfile'
import nginx from 'highlight.js/lib/languages/nginx'
import powershell from 'highlight.js/lib/languages/powershell'

hljs.registerLanguage('dart', dart)
hljs.registerLanguage('dockerfile', dockerfile)
hljs.registerLanguage('nginx', nginx)
hljs.registerLanguage('powershell', powershell)
hljs.registerAliases('vue', { languageName: 'xml' })

const autoDetectLanguages = [
  'bash',
  'javascript',
  'typescript',
  'python',
  'json',
  'yaml',
  'sql',
  'xml',
]

export function highlightCode(source: string, language?: string): string | undefined {
  if (!language) return hljs.highlightAuto(source, autoDetectLanguages).value

  const normalized = language.toLowerCase()
  const grammar = normalized === 'shell' || normalized === 'zsh' ? 'bash' : normalized
  if (!hljs.getLanguage(grammar)) return undefined

  return hljs.highlight(source, { language: grammar, ignoreIllegals: true }).value
}

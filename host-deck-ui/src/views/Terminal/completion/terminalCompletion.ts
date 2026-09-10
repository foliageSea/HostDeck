import type { TerminalSnippet } from '@/api/terminal'

export type TerminalCompletionSource = 'snippet' | 'history' | 'command'

export interface TerminalCompletionItem {
  command: string
  detail?: string
  id: string
  source: TerminalCompletionSource
}

interface RankedCompletion extends TerminalCompletionItem {
  rank: number
}

const MAX_HISTORY_ITEMS = 100

const COMMON_COMMANDS = [
  'alias',
  'awk',
  'bash',
  'bat',
  'brew',
  'cat',
  'cd',
  'chmod',
  'chown',
  'clear',
  'cp',
  'curl',
  'date',
  'df',
  'diff',
  'docker compose',
  'docker exec',
  'docker images',
  'docker logs',
  'docker ps',
  'docker pull',
  'docker restart',
  'docker stop',
  'du',
  'env',
  'exit',
  'fd',
  'find',
  'free',
  'git add',
  'git branch',
  'git checkout',
  'git clone',
  'git commit',
  'git diff',
  'git fetch',
  'git log',
  'git pull',
  'git push',
  'git restore',
  'git status',
  'grep',
  'history',
  'htop',
  'ip',
  'journalctl',
  'kill',
  'less',
  'ln',
  'ls',
  'mkdir',
  'mv',
  'nano',
  'netstat',
  'npm install',
  'npm run',
  'npx',
  'ping',
  'pnpm add',
  'pnpm build',
  'pnpm dev',
  'pnpm install',
  'ps',
  'pwd',
  'rg',
  'rm',
  'rsync',
  'scp',
  'sed',
  'ssh',
  'sudo',
  'systemctl restart',
  'systemctl status',
  'tail',
  'tar',
  'top',
  'touch',
  'tree',
  'uname',
  'unzip',
  'vim',
  'wget',
  'which',
  'whoami',
  'yarn',
  'zip',
] as const

function removeLastCharacter(value: string) {
  return Array.from(value).slice(0, -1).join('')
}

function removeLastWord(value: string) {
  return value.replace(/\s*\S+\s*$/, '')
}

function includesControlCharacter(value: string) {
  return Array.from(value).some((character) => {
    const codePoint = character.codePointAt(0) ?? 0
    return codePoint < 0x20 || codePoint === 0x7f
  })
}

export class TerminalInputModel {
  private currentLine = ''
  private inputReliable = true
  private readonly historyItems: string[] = []

  get history() {
    return [...this.historyItems]
  }

  get line() {
    return this.currentLine
  }

  get reliable() {
    return this.inputReliable
  }

  handleData(data: string) {
    if (!data) {
      return
    }

    if (data === '\r' || data === '\n') {
      this.commitLine()
      return
    }

    if (data === '\x03') {
      this.resetLine()
      return
    }

    if (!this.inputReliable) {
      return
    }

    if (data === '\x7f' || data === '\b') {
      this.currentLine = removeLastCharacter(this.currentLine)
      return
    }

    if (data === '\x17') {
      this.currentLine = removeLastWord(this.currentLine)
      return
    }

    if (data === '\x15') {
      this.currentLine = ''
      return
    }

    const pastedText = this.readBracketedPaste(data)
    if (pastedText !== null) {
      this.appendText(pastedText)
      return
    }

    if (includesControlCharacter(data)) {
      this.inputReliable = false
      return
    }

    this.currentLine += data
  }

  resetLine() {
    this.currentLine = ''
    this.inputReliable = true
  }

  suspendLine() {
    this.currentLine = ''
    this.inputReliable = false
  }

  private appendText(value: string) {
    if (value.includes('\r') || value.includes('\n')) {
      this.inputReliable = false
      return
    }
    this.currentLine += value
  }

  private commitLine() {
    if (this.inputReliable) {
      const command = this.currentLine.trim()
      if (command) {
        const existingIndex = this.historyItems.indexOf(command)
        if (existingIndex !== -1) {
          this.historyItems.splice(existingIndex, 1)
        }
        this.historyItems.unshift(command)
        this.historyItems.splice(MAX_HISTORY_ITEMS)
      }
    }
    this.resetLine()
  }

  private readBracketedPaste(data: string) {
    const start = '\x1b[200~'
    const end = '\x1b[201~'
    if (!data.startsWith(start) || !data.endsWith(end)) {
      return null
    }
    return data.slice(start.length, -end.length)
  }
}

function matchRank(command: string, query: string) {
  const normalizedCommand = command.toLocaleLowerCase()
  const normalizedQuery = query.toLocaleLowerCase()
  if (normalizedCommand.startsWith(normalizedQuery)) {
    return 0
  }
  return null
}

export function buildTerminalCompletions(
  query: string,
  snippets: TerminalSnippet[],
  history: string[],
  limit = 8,
) {
  const normalizedQuery = query.trimStart()
  if (normalizedQuery.length < 2 || normalizedQuery !== query || query.trimEnd() !== query) {
    return []
  }

  const candidates: RankedCompletion[] = [
    ...snippets.map((snippet, index) => ({
      command: snippet.command,
      detail: snippet.name,
      id: `snippet:${snippet.id}`,
      rank: index,
      source: 'snippet' as const,
    })),
    ...history.map((command, index) => ({
      command,
      id: `history:${index}:${command}`,
      rank: index,
      source: 'history' as const,
    })),
    ...COMMON_COMMANDS.map((command, index) => ({
      command,
      id: `command:${command}`,
      rank: index,
      source: 'command' as const,
    })),
  ]

  const sourceRank: Record<TerminalCompletionSource, number> = {
    snippet: 0,
    history: 1,
    command: 2,
  }
  const seen = new Set<string>()

  return candidates
    .map((candidate) => ({ candidate, match: matchRank(candidate.command, normalizedQuery) }))
    .filter(
      (entry): entry is { candidate: RankedCompletion; match: number } =>
        entry.match !== null && entry.candidate.command !== normalizedQuery,
    )
    .sort(
      (left, right) =>
        left.match - right.match ||
        sourceRank[left.candidate.source] - sourceRank[right.candidate.source] ||
        left.candidate.rank - right.candidate.rank ||
        left.candidate.command.localeCompare(right.candidate.command),
    )
    .filter(({ candidate }) => {
      const key = candidate.command.toLocaleLowerCase()
      if (seen.has(key)) {
        return false
      }
      seen.add(key)
      return true
    })
    .slice(0, limit)
    .map(({ candidate: { rank: _rank, ...candidate } }) => candidate)
}

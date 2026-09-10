import { describe, expect, it } from 'vitest'
import type { TerminalSnippet } from '@/api/terminal'
import { buildTerminalCompletions, TerminalInputModel } from '../terminalCompletion'

const snippets: TerminalSnippet[] = [
  {
    command: 'docker logs --follow api',
    createdAt: 1,
    id: 1,
    name: '跟踪 API 日志',
    updatedAt: 1,
  },
]

describe('TerminalInputModel', () => {
  it('tracks text editing at the end of the line', () => {
    const model = new TerminalInputModel()

    model.handleData('docker ps')
    model.handleData('\x7f')
    model.handleData('\x17')
    expect(model.line).toBe('docker')

    model.handleData('logs')
    model.handleData('\x15')
    expect(model.line).toBe('')
  })

  it('stores submitted commands in recent-first order without duplicates', () => {
    const model = new TerminalInputModel()

    model.handleData('git status')
    model.handleData('\r')
    model.handleData('docker ps')
    model.handleData('\r')
    model.handleData('git status')
    model.handleData('\r')

    expect(model.history).toEqual(['git status', 'docker ps'])
    expect(model.line).toBe('')
  })

  it('supports unicode and single-line bracketed paste', () => {
    const model = new TerminalInputModel()

    model.handleData('echo 你好')
    model.handleData('\x7f')
    model.handleData('\x1b[200~世界\x1b[201~')

    expect(model.line).toBe('echo 你世界')
    expect(model.reliable).toBe(true)
  })

  it('pauses tracking after cursor movement or multiline paste until reset', () => {
    const model = new TerminalInputModel()

    model.handleData('git')
    model.handleData('\x1b[D')
    model.handleData('x')
    expect(model.reliable).toBe(false)
    expect(model.line).toBe('git')

    model.handleData('\r')
    expect(model.reliable).toBe(true)
    expect(model.line).toBe('')

    model.handleData('\x1b[200~one\ntwo\x1b[201~')
    expect(model.reliable).toBe(false)
  })

  it('discards the current line on Ctrl+C', () => {
    const model = new TerminalInputModel()
    model.handleData('secret')
    model.handleData('\x03')

    expect(model.line).toBe('')
    expect(model.history).toEqual([])
  })

  it('does not retain suspended sensitive input', () => {
    const model = new TerminalInputModel()
    model.suspendLine()
    model.handleData('secret-token')
    model.handleData('\r')

    expect(model.history).toEqual([])
    expect(model.reliable).toBe(true)
  })
})

describe('buildTerminalCompletions', () => {
  it('prioritizes snippets, history and prefix matches while removing duplicates', () => {
    const completions = buildTerminalCompletions('docker l', snippets, [
      'docker logs --follow api',
      'docker login',
    ])

    expect(completions.map((item) => [item.source, item.command])).toEqual([
      ['snippet', 'docker logs --follow api'],
      ['history', 'docker login'],
      ['command', 'docker logs'],
    ])
  })

  it('only returns prefix matches that can be appended safely', () => {
    const completions = buildTerminalCompletions('git st', [], ['git stash', 'git status'])

    expect(completions.slice(0, 2).map((item) => item.command)).toEqual(['git stash', 'git status'])
    expect(buildTerminalCompletions('g st', [], ['git status'])).toEqual([])
  })

  it('does not suggest for short, indented or completed input', () => {
    expect(buildTerminalCompletions('g', snippets, [])).toEqual([])
    expect(buildTerminalCompletions(' git', snippets, [])).toEqual([])
    expect(buildTerminalCompletions('docker logs --follow api', snippets, [])).toEqual([])
  })
})

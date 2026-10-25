import { execFileSync } from 'node:child_process'
import { describe, expect, it } from 'vitest'
import { buildCwdHookCommand, parseOsc7Path } from '../terminalCwd'

describe('parseOsc7Path', () => {
  it('解析带主机名的 file URI', () => {
    expect(parseOsc7Path('file://my-host/home/user/project')).toBe('/home/user/project')
  })

  it('解析空主机名', () => {
    expect(parseOsc7Path('file:///var/log')).toBe('/var/log')
  })

  it('解码百分号编码的路径', () => {
    expect(parseOsc7Path('file://h/tmp/a%20b/%E4%B8%AD%E6%96%87')).toBe('/tmp/a b/中文')
    expect(parseOsc7Path('file://h/tmp/100%25')).toBe('/tmp/100%')
  })

  it('保留未编码的空格与非法转义', () => {
    expect(parseOsc7Path('file://h/tmp/a b')).toBe('/tmp/a b')
    expect(parseOsc7Path('file://h/tmp/%zz')).toBe('/tmp/%zz')
  })

  it('非 file URI 返回 null', () => {
    expect(parseOsc7Path('/tmp')).toBeNull()
    expect(parseOsc7Path('')).toBeNull()
  })
})

describe('buildCwdHookCommand', () => {
  it('是单行命令', () => {
    expect(buildCwdHookCommand()).not.toMatch(/[\r\n]/)
  })

  it.each(['bash', 'zsh'])('在 %s 中输出可解析的 OSC 7', (shell) => {
    const script = buildCwdHookCommand()
    const output = (() => {
      try {
        return execFileSync(
          shell,
          ['-c', `cd "/tmp"; mkdir -p "/tmp/hd 100%"; cd "/tmp/hd 100%"; ${script}`],
          {
            encoding: 'utf8',
          },
        )
      } catch {
        return null
      }
    })()
    if (output === null) {
      return
    }

    // eslint-disable-next-line no-control-regex
    const match = /\u001b\]7;([^\u001b]*)\u001b\\/.exec(output)
    expect(match).not.toBeNull()
    expect(parseOsc7Path(match![1])).toMatch(/\/tmp\/hd 100%$/)
  })
})

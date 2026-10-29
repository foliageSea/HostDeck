import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { getUiApi, installUiApi } from '@/lib/ui'
import {
  describeFileOpenError,
  notifyFileOpenError,
  resetNotifyOnceCache,
  shouldNotifyOnce,
} from '@/views/Files/utils'

const messageError = vi.fn()

function installFakeUi() {
  installUiApi({
    dialog: {} as never,
    loadingBar: {} as never,
    message: { error: messageError } as never,
    notification: {} as never,
  })
}

describe('describeFileOpenError', () => {
  it('explains permission denied failures from the SSH error text', () => {
    const error = new Error('SftpStatusError: Permission denied(code 3)')

    expect(describeFileOpenError('/root', error)).toBe(
      '无法打开目录 /root：权限不足，无法访问该目录。',
    )
  })

  it('explains missing directories', () => {
    expect(describeFileOpenError('/opt/gone', new Error('No such file (2)'))).toBe(
      '无法打开目录 /opt/gone：目录不存在或已被删除。',
    )
    expect(describeFileOpenError('/opt/gone', { response: { status: 404 } })).toBe(
      '无法打开目录 /opt/gone：目录不存在或已被删除。',
    )
  })

  it('keeps the backend message for other failures', () => {
    expect(describeFileOpenError('/var/log', new Error('连接已断开'))).toBe(
      '无法打开目录 /var/log：连接已断开',
    )
  })

  it('falls back to a generic description when the error carries no message', () => {
    expect(describeFileOpenError('/srv', {})).toBe(
      '无法打开目录 /srv：无法访问该目录，请稍后重试。',
    )
    expect(describeFileOpenError('', null)).toBe(
      '无法打开目录 该目录：无法访问该目录，请稍后重试。',
    )
  })
})

describe('shouldNotifyOnce', () => {
  beforeEach(() => {
    resetNotifyOnceCache()
  })

  it('suppresses repeated notifications inside the dedupe window', () => {
    expect(shouldNotifyOnce('open:/root', { now: 1000 })).toBe(true)
    expect(shouldNotifyOnce('open:/root', { now: 1500 })).toBe(false)
    expect(shouldNotifyOnce('open:/root', { now: 2600 })).toBe(true)
  })

  it('tracks different keys independently', () => {
    expect(shouldNotifyOnce('open:/root', { now: 1000 })).toBe(true)
    expect(shouldNotifyOnce('open:/var', { now: 1000 })).toBe(true)
  })
})

describe('notifyFileOpenError', () => {
  beforeEach(() => {
    resetNotifyOnceCache()
    messageError.mockReset()
    installFakeUi()
  })

  afterEach(() => {
    resetNotifyOnceCache()
  })

  it('shows a message bubble once for the same failure', () => {
    const error = new Error('SftpStatusError: Permission denied(code 3)')

    notifyFileOpenError('/root', error)
    notifyFileOpenError('/root', error)

    expect(messageError).toHaveBeenCalledTimes(1)
    expect(messageError).toHaveBeenCalledWith('无法打开目录 /root：权限不足，无法访问该目录。')
    expect(() => getUiApi()).not.toThrow()
  })

  it('dedupes by error kind even when the backend wording changes', () => {
    notifyFileOpenError('/root', new Error('SftpStatusError: Permission denied(code 3)'))
    notifyFileOpenError('/root', new Error('权限不足，无法访问该目录。'))
    notifyFileOpenError('/root', new Error('权限不足，无法访问该目录或文件，请联系管理员检查 SSH 用户权限。'))

    expect(messageError).toHaveBeenCalledTimes(1)
  })

  it('still reports a different directory', () => {
    notifyFileOpenError('/root', new Error('Permission denied(code 3)'))
    notifyFileOpenError('/etc/ssh', new Error('Permission denied(code 3)'))

    expect(messageError).toHaveBeenCalledTimes(2)
    expect(messageError).toHaveBeenLastCalledWith(
      '无法打开目录 /etc/ssh：权限不足，无法访问该目录。',
    )
  })
})

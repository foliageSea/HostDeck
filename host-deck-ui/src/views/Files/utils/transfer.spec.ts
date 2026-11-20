import { AxiosError } from 'axios'
import { describe, expect, it } from 'vitest'
import { getUploadErrorMessage } from './transfer'

describe('upload error message', () => {
  it('preserves errors returned by the server', () => {
    expect(getUploadErrorMessage(new AxiosError('远端目录权限不足。', 'ERR_BAD_REQUEST'))).toBe(
      '远端目录权限不足。',
    )
  })

  it('does not imply a remote cause when the browser never received a response', () => {
    expect(getUploadErrorMessage(new AxiosError('Network Error', 'ERR_NETWORK'))).toContain(
      '未收到服务器响应',
    )
  })
})

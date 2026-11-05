import { effectScope } from 'vue'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useLoginConnection } from '../useLoginConnection'

const api = vi.hoisted(() => ({ connect: vi.fn(), cancelConnect: vi.fn(), disconnect: vi.fn() }))
vi.mock('@/api/auth', () => ({ authApi: api }))

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (error: Error) => void
  const promise = new Promise<T>((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}

const payload = { host: 'example.com', port: 22, username: 'user', serverId: 1 }
const scopes: ReturnType<typeof effectScope>[] = []
function setup() {
  const scope = effectScope()
  scopes.push(scope)
  const callbacks = { onSuccess: vi.fn(), onError: vi.fn(), onCancel: vi.fn() }
  const connection = scope.run(() => useLoginConnection(callbacks))!
  return { ...connection, ...callbacks, scope }
}

describe('login connection cancellation', () => {
  beforeEach(() => {
    vi.resetAllMocks()
    api.cancelConnect.mockResolvedValue({ success: true })
    api.disconnect.mockResolvedValue({ success: true })
  })
  afterEach(() => {
    scopes.splice(0).forEach((scope) => scope.stop())
  })

  it('aborts immediately without displaying a connection failure', async () => {
    const pending = deferred<{ connectionId: string }>()
    api.connect.mockReturnValue(pending.promise)
    const state = setup()
    const result = state.connect(payload)
    expect(state.isConnecting.value).toBe(true)
    const options = api.connect.mock.calls[0]![1]
    state.cancel()
    expect(options.signal.aborted).toBe(true)
    expect(api.cancelConnect).toHaveBeenCalledWith(options.requestId)
    expect(state.isConnecting.value).toBe(false)
    pending.reject(new Error('cancelled'))
    await result
    expect(state.onCancel).toHaveBeenCalledOnce()
    expect(state.onError).not.toHaveBeenCalled()
  })

  it('allows retry and cleans up stale success without affecting the new attempt', async () => {
    const old = deferred<{ connectionId: string }>()
    const retry = deferred<{ connectionId: string }>()
    api.connect.mockReturnValueOnce(old.promise).mockReturnValueOnce(retry.promise)
    const state = setup()
    const first = state.connect(payload)
    state.cancel()
    const second = state.connect({ ...payload, host: 'new.example.com' })
    old.resolve({ connectionId: 'old' })
    await first
    expect(api.disconnect).toHaveBeenCalledWith('old')
    expect(state.isConnecting.value).toBe(true)
    expect(state.onSuccess).not.toHaveBeenCalled()
    retry.resolve({ connectionId: 'new' })
    await second
    expect(state.onSuccess).toHaveBeenCalledWith(
      { connectionId: 'new' },
      { ...payload, host: 'new.example.com' },
    )
    expect(state.isConnecting.value).toBe(false)
  })

  it('cancels when the login screen is disposed', async () => {
    const pending = deferred<{ connectionId: string }>()
    api.connect.mockReturnValue(pending.promise)
    const state = setup()
    const result = state.connect(payload)
    state.scope.stop()
    expect(api.cancelConnect).toHaveBeenCalledOnce()
    pending.reject(new Error('cancelled'))
    await result
    expect(state.onError).not.toHaveBeenCalled()
  })

  it('reports genuine failures and prevents duplicate submissions', async () => {
    const pending = deferred<{ connectionId: string }>()
    api.connect.mockReturnValue(pending.promise)
    const state = setup()
    const result = state.connect(payload)
    await state.connect(payload)
    expect(api.connect).toHaveBeenCalledOnce()
    const error = new Error('authentication failed')
    pending.reject(error)
    await result
    expect(state.onError).toHaveBeenCalledWith(error)
    expect(state.isConnecting.value).toBe(false)
  })
})

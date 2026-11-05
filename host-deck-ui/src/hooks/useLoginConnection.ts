import { onScopeDispose, ref } from 'vue'
import { authApi, type ConnectParams, type ConnectResponse } from '@/api/auth'

export function useLoginConnection(callbacks: {
  onSuccess: (response: ConnectResponse, payload: ConnectParams) => void
  onError: (error: unknown) => void
  onCancel: () => void
}) {
  const isConnecting = ref(false)
  let active: { requestId: string; controller: AbortController } | null = null

  function cancel() {
    const attempt = active
    if (!attempt) return
    active = null
    isConnecting.value = false
    attempt.controller.abort()
    callbacks.onCancel()
    void authApi.cancelConnect(attempt.requestId).catch(() => {
      // Retry once in case the cancellation request raced a transient failure.
      void authApi.cancelConnect(attempt.requestId).catch(() => {})
    })
  }

  async function connect(payload: ConnectParams) {
    if (active) return
    const attempt = {
      requestId: Array.from(crypto.getRandomValues(new Uint8Array(16)), (byte) =>
        byte.toString(16).padStart(2, '0'),
      ).join(''),
      controller: new AbortController(),
    }
    active = attempt
    isConnecting.value = true
    const snapshot = { ...payload }
    try {
      const response = await authApi.connect(snapshot, {
        requestId: attempt.requestId,
        signal: attempt.controller.signal,
      })
      if (active !== attempt) {
        void authApi.disconnect(response.connectionId).catch(() => {})
        return
      }
      active = null
      isConnecting.value = false
      callbacks.onSuccess(response, snapshot)
    } catch (error) {
      if (active === attempt) {
        active = null
        isConnecting.value = false
        callbacks.onError(error)
      }
    }
  }

  onScopeDispose(cancel)
  return { cancel, connect, isConnecting }
}

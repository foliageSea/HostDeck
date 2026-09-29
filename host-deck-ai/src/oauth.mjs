import { openaiCodexProvider } from '@earendil-works/pi-ai/providers/openai-codex'

export const codexOAuth = openaiCodexProvider().auth.oauth

export async function loginCodex(emit, signal, oauth = codexOAuth) {
  const credential = await oauth.login({
    signal,
    prompt: async (prompt) => {
      if (prompt.type === 'select' && prompt.options.some((item) => item.id === 'device_code')) {
        return 'device_code'
      }
      throw new Error('Unsupported OAuth interaction.')
    },
    notify: (event) => {
      if (event.type === 'device_code') {
        emit({ type: 'auth', userCode: event.userCode,
          verificationUri: event.verificationUri, expiresInSeconds: event.expiresInSeconds ?? 900 })
      }
    },
  })
  emit({ type: 'result', credential })
}

export async function refreshCodex(credential, emit, signal, oauth = codexOAuth) {
  emit({ type: 'result', credential: await oauth.refresh(credential, signal) })
}

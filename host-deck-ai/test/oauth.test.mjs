import assert from 'node:assert/strict'
import { test } from 'node:test'
import { loginCodex, refreshCodex } from '../src/oauth.mjs'
import { catalog, invoke, resolveModel } from '../src/model.mjs'

const accessToken = `header.${Buffer.from(JSON.stringify({
  'https://api.openai.com/auth': { chatgpt_account_id: 'test-account' },
})).toString('base64')}.signature`

test('SDK device-code login and refresh exchange credentials using official auth endpoints', async (t) => {
  const requests = []
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    requests.push({ url: String(url), body: String(options.body) })
    if (String(url).endsWith('/usercode')) {
      return Response.json({ device_auth_id: 'device-id', user_code: 'ABCD-1234', interval: 0 })
    }
    if (String(url).endsWith('/deviceauth/token')) {
      return Response.json({ authorization_code: 'authorization-code', code_verifier: 'verifier' })
    }
    assert.equal(String(url), 'https://auth.openai.com/oauth/token')
    return Response.json({ access_token: accessToken, refresh_token: 'rotated-refresh', expires_in: 3600 })
  })
  const events = []
  const signal = new AbortController().signal
  await loginCodex((event) => events.push(event), signal)
  assert.deepEqual(events[0], {
    type: 'auth', userCode: 'ABCD-1234', verificationUri: 'https://auth.openai.com/codex/device', expiresInSeconds: 900,
  })
  const credential = events[1].credential
  assert.equal(credential.type, 'oauth')
  assert.equal(credential.accountId, 'test-account')
  assert.equal(credential.access, accessToken)
  assert.ok(credential.expires > Date.now())
  assert.ok(requests[2].body.includes('grant_type=authorization_code'))
  assert.ok(requests[2].body.includes('code_verifier=verifier'))
  const refreshed = []
  await refreshCodex(credential, (event) => refreshed.push(event), signal)
  assert.ok(requests.at(-1).body.includes('grant_type=refresh_token'))
  assert.ok(requests.at(-1).body.includes('refresh_token=rotated-refresh'))
  assert.equal(refreshed[0].credential.access, accessToken)
})

test('device-code login honors cancellation while waiting for approval', async (t) => {
  const controller = new AbortController()
  t.mock.method(globalThis, 'fetch', async (url) => {
    assert.ok(String(url).endsWith('/usercode'))
    return Response.json({ device_auth_id: 'device-id', user_code: 'ABCD-1234', interval: 10 })
  })
  await assert.rejects(loginCodex(() => controller.abort(), controller.signal))
})

test('Codex catalog and inference use subscription auth at a fixed endpoint', async (t) => {
  const entry = catalog().find((provider) => provider.id === 'openai-codex').models[0]
  const settings = { provider: 'openai-codex', model: entry.id, baseUrl: 'https://untrusted.example',
    credential: { type: 'oauth', access: accessToken, refresh: 'refresh', expires: Date.now() + 3600000 } }
  assert.equal(resolveModel(settings).baseUrl, 'https://chatgpt.com/backend-api')
  let called = false
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    called = true
    assert.ok(String(url).startsWith('https://chatgpt.com/backend-api/'))
    const headers = new Headers(options.headers)
    assert.equal(headers.get('authorization'), `Bearer ${accessToken}`)
    assert.equal(headers.get('chatgpt-account-id'), 'test-account')
    const item = { id: 'msg_1', type: 'message', role: 'assistant', status: 'completed', content: [{ type: 'output_text', text: 'Codex ready', annotations: [] }] }
    const events = [
      { type: 'response.created', response: { id: 'resp_1', status: 'in_progress', output: [] } },
      { type: 'response.output_item.added', output_index: 0, item: { ...item, content: [] } },
      { type: 'response.content_part.added', output_index: 0, content_index: 0, part: { type: 'output_text', text: '', annotations: [] } },
      { type: 'response.output_text.delta', output_index: 0, content_index: 0, delta: 'Codex ready' },
      { type: 'response.output_item.done', output_index: 0, item },
      { type: 'response.completed', response: { id: 'resp_1', status: 'completed', output: [item], usage: { input_tokens: 4, output_tokens: 2, total_tokens: 6 } } },
    ]
    return new Response(events.map((event) => `data: ${JSON.stringify(event)}\n\n`).join(''), {
      headers: { 'content-type': 'text/event-stream' },
    })
  })
  const output = []
  await invoke({ settings, messages: [{ role: 'user', content: 'Hello' }], tools: [] },
    (event) => output.push(event), new AbortController().signal)
  assert.ok(called)
  assert.equal(output.at(-1).text, 'Codex ready')
  assert.equal(output.at(-1).providerMessage.provider, 'openai-codex')
})

test('catalog providers accept custom model IDs with their configured protocol', () => {
  const model = resolveModel({
    provider: 'openai',
    model: 'company-preview-model',
    api: 'openai-responses',
    baseUrl: 'https://gateway.example.test/v1',
  })
  assert.equal(model.id, 'company-preview-model')
  assert.equal(model.provider, 'openai')
  assert.equal(model.api, 'openai-responses')
  assert.equal(model.baseUrl, 'https://gateway.example.test/v1')
})

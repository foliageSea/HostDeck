import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createServer } from 'node:http'
import { spawn } from 'node:child_process'
import { toContext, resolveModel } from '../src/model.mjs'

function bridge(request) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['dist/bridge.mjs'], { stdio: ['pipe', 'pipe', 'pipe'] })
    let output = ''
    let errors = ''
    child.stdout.on('data', (chunk) => { output += chunk })
    child.stderr.on('data', (chunk) => { errors += chunk })
    child.on('error', reject)
    child.on('close', (code) => {
      try { resolve({ code, errors, events: output.trim().split('\n').filter(Boolean).map(JSON.parse) }) }
      catch (error) { reject(error) }
    })
    child.stdin.end(`${JSON.stringify(request)}\n`)
  })
}

async function upstream(t, handler) {
  const server = createServer(async (req, res) => {
    const chunks = []
    for await (const chunk of req) chunks.push(chunk)
    handler(req, res, JSON.parse(Buffer.concat(chunks)))
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  t.after(() => { server.closeAllConnections(); server.close() })
  return `http://127.0.0.1:${server.address().port}`
}

const request = (baseUrl, api = 'openai-completions') => ({
  type: 'invoke', settings: { provider: 'custom', api, baseUrl, model: 'test-model', apiKey: 'test-secret' },
  messages: [{ role: 'system', content: 'Be helpful.' }, { role: 'user', content: 'Hi' }], tools: [],
})
const sse = (res, data, event) => res.write(`${event ? `event: ${event}\n` : ''}data: ${JSON.stringify(data)}\n\n`)

test('bundled bridge returns catalog without credentials', async () => {
  const result = await bridge({ type: 'catalog' })
  assert.equal(result.code, 0, result.errors)
  for (const id of ['openai', 'anthropic', 'google', 'deepseek']) {
    assert.ok(result.events[0].providers.find((provider) => provider.id === id)?.models.length)
  }
})

test('Chat Completions streams text, validates fragmented tool JSON and reports usage', async (t) => {
  let payload
  const url = await upstream(t, (req, res, body) => {
    payload = body
    assert.equal(req.url, '/v1/chat/completions')
    assert.equal(req.headers.authorization, 'Bearer test-secret')
    res.writeHead(200, { 'content-type': 'text/event-stream' })
    for (const delta of [
      { role: 'assistant', content: 'Checking.' },
      { tool_calls: [{ index: 0, id: 'call_1', type: 'function', function: { name: 'status', arguments: '{"host":' } }] },
      { tool_calls: [{ index: 0, function: { arguments: '"server"}' } }] },
    ]) sse(res, { id: 'chat-1', object: 'chat.completion.chunk', choices: [{ index: 0, delta, finish_reason: null }] })
    sse(res, { id: 'chat-1', choices: [{ index: 0, delta: {}, finish_reason: 'tool_calls' }], usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } })
    res.end('data: [DONE]\n\n')
  })
  const input = request(`${url}/v1`)
  input.tools = [{ name: 'status', description: 'Get status', parameters: { type: 'object', properties: { host: { type: 'string' } }, required: ['host'] } }]
  const result = await bridge(input)
  assert.equal(result.code, 0, JSON.stringify(result))
  assert.equal(payload.tools[0].function.name, 'status')
  assert.equal(result.events.find((event) => event.type === 'text').text, 'Checking.')
  const final = result.events.at(-1)
  assert.deepEqual(final.toolCalls, [{ id: 'call_1', name: 'status', arguments: { host: 'server' } }])
  assert.equal(final.usage.totalTokens, 15)
  assert.equal(final.providerMessage.stopReason, 'toolUse')
})

test('Anthropic uses Messages headers and SSE protocol', async (t) => {
  const url = await upstream(t, (req, res, body) => {
    assert.match(req.url, /^\/v1\/messages(?:\?|$)/)
    assert.equal(req.headers['x-api-key'], 'test-secret')
    assert.ok(body.system)
    res.writeHead(200, { 'content-type': 'text/event-stream' })
    const events = [
      { type: 'message_start', message: { id: 'msg_1', role: 'assistant', model: 'test-model', content: [], usage: { input_tokens: 8, output_tokens: 0 } } },
      { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
      { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'Hello' } },
      { type: 'content_block_stop', index: 0 },
      { type: 'message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 2 } },
      { type: 'message_stop' },
    ]
    for (const event of events) sse(res, event, event.type)
    res.end()
  })
  const result = await bridge(request(url, 'anthropic-messages'))
  assert.equal(result.code, 0, JSON.stringify(result))
  assert.equal(result.events.at(-1).text, 'Hello')
  assert.equal(result.events.at(-1).usage.promptTokens, 8)
})

test('Google Gemini uses its native streaming endpoint', async (t) => {
  const url = await upstream(t, (req, res, body) => {
    assert.match(req.url, /models\/test-model:streamGenerateContent/)
    assert.equal(body.contents[0].role, 'user')
    res.writeHead(200, { 'content-type': 'text/event-stream' })
    sse(res, { candidates: [{ content: { role: 'model', parts: [{ text: 'Hello Gemini' }] }, finishReason: 'STOP', index: 0 }], usageMetadata: { promptTokenCount: 4, candidatesTokenCount: 2, totalTokenCount: 6 } })
    res.end()
  })
  const result = await bridge(request(`${url}/v1beta`, 'google-generative-ai'))
  assert.equal(result.code, 0, JSON.stringify(result))
  assert.equal(result.events.at(-1).text, 'Hello Gemini')
})

test('OpenAI Responses uses its native streaming endpoint', async (t) => {
  const url = await upstream(t, (req, res) => {
    assert.equal(req.url, '/v1/responses')
    res.writeHead(200, { 'content-type': 'text/event-stream' })
    const item = { id: 'msg_1', type: 'message', role: 'assistant', status: 'completed', content: [{ type: 'output_text', text: 'Hello Responses', annotations: [] }] }
    const events = [
      { type: 'response.created', response: { id: 'resp_1', status: 'in_progress', output: [] } },
      { type: 'response.output_item.added', output_index: 0, item: { ...item, status: 'in_progress', content: [] } },
      { type: 'response.content_part.added', output_index: 0, content_index: 0, part: { type: 'output_text', text: '', annotations: [] } },
      { type: 'response.output_text.delta', output_index: 0, content_index: 0, delta: 'Hello Responses' },
      { type: 'response.output_item.done', output_index: 0, item },
      { type: 'response.completed', response: { id: 'resp_1', status: 'completed', output: [item], usage: { input_tokens: 4, output_tokens: 2, total_tokens: 6 } } },
    ]
    for (const event of events) sse(res, event, event.type)
    res.end()
  })
  const result = await bridge(request(`${url}/v1`, 'openai-responses'))
  assert.equal(result.code, 0, JSON.stringify(result))
  assert.equal(result.events.at(-1).text, 'Hello Responses')
})

test('upstream failures produce a terminal error without echoing secrets', async (t) => {
  const url = await upstream(t, (_req, res) => {
    res.writeHead(401, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ error: { message: 'bad key test-secret' } }))
  })
  const result = await bridge(request(url))
  assert.equal(result.code, 1)
  assert.equal(result.events.at(-1).type, 'error')
  assert.ok(!JSON.stringify(result).includes('test-secret'))
})

test('restored context retains signatures, filters orphan calls and maps images/results', () => {
  const model = resolveModel({ ...request('http://localhost').settings })
  const context = toContext([
    { role: 'user', content: '', attachments: [{ data: 'YWJj', mimeType: 'image/png' }] },
    { role: 'assistant', toolCalls: [{ id: 'kept', name: 'status', arguments: {} }], providerMessage: {
      role: 'assistant', provider: 'anthropic', content: [
        { type: 'thinking', thinking: '', thinkingSignature: 'opaque' },
        { type: 'toolCall', id: 'kept', name: 'status', arguments: {} },
        { type: 'toolCall', id: 'orphan', name: 'status', arguments: {} },
      ],
    } },
    { role: 'tool', toolCallId: 'kept', content: 'Denied', isError: true },
  ], [], model)
  assert.equal(context.messages[0].content[0].type, 'image')
  assert.equal(context.messages[1].content[0].thinkingSignature, 'opaque')
  assert.equal(context.messages[1].content.length, 2)
  assert.equal(context.messages[2].toolName, 'status')
  assert.equal(context.messages[2].isError, true)
})

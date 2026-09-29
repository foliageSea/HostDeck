import { createModels, createProvider, validateToolCall } from '@earendil-works/pi-ai'
import { getBuiltinModels, getBuiltinProviders } from '@earendil-works/pi-ai/providers/all'
import { openAICompletionsApi } from '@earendil-works/pi-ai/api/openai-completions.lazy'
import { openAIResponsesApi } from '@earendil-works/pi-ai/api/openai-responses.lazy'
import { anthropicMessagesApi } from '@earendil-works/pi-ai/api/anthropic-messages.lazy'
import { googleGenerativeAIApi } from '@earendil-works/pi-ai/api/google-generative-ai.lazy'
import { openAICodexResponsesApi } from '@earendil-works/pi-ai/api/openai-codex-responses.lazy'
import { codexOAuth } from './oauth.mjs'

const apis = {
  'openai-codex-responses': openAICodexResponsesApi(),
  'openai-completions': openAICompletionsApi(),
  'openai-responses': openAIResponsesApi(),
  'anthropic-messages': anthropicMessagesApi(),
  'google-generative-ai': googleGenerativeAIApi(),
}
const zeroUsage = () => ({
  input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
})

// Codex uses encrypted OAuth credentials managed and refreshed by Dart.
export function catalog() {
  return getBuiltinProviders()
    .filter((id) => !['github-copilot', 'google-vertex', 'amazon-bedrock'].includes(id))
    .map((id) => ({
      id,
      models: getBuiltinModels(id).filter((model) => apis[model.api]).map((model) => ({
        id: model.id, name: model.name, api: model.api, baseUrl: model.baseUrl,
        reasoning: model.reasoning, input: model.input,
      })),
    }))
    .filter((provider) => provider.models.length)
}

export function resolveModel(settings) {
  const builtin = settings.provider === 'custom' ? undefined
    : getBuiltinModels(settings.provider).find((model) => model.id === settings.model)
  if (settings.provider !== 'custom' && !builtin) throw new Error('Model is not in the selected provider catalog.')
  // Subscription tokens must only be sent to the provider's built-in endpoint.
  const model = builtin ? { ...builtin, baseUrl: settings.provider === 'openai-codex' ? builtin.baseUrl : settings.baseUrl } : {
    id: settings.model, name: settings.model, provider: 'hostdeck-custom',
    api: settings.api, baseUrl: settings.baseUrl, reasoning: false,
    input: ['text', 'image'], contextWindow: 128000, maxTokens: 4096,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  }
  if (!apis[model.api]) throw new Error('Unsupported model API.')
  if (model.api === 'openai-codex-responses' && settings.provider !== 'openai-codex') {
    throw new Error('Codex requires the OpenAI Codex provider.')
  }
  return model
}

export function toContext(messages, tools, model) {
  const calls = new Map()
  const context = { systemPrompt: '', messages: [], tools }
  for (const message of messages) {
    const timestamp = Date.now()
    if (message.role === 'system') {
      context.systemPrompt += `${message.content}\n`
    } else if (message.role === 'user') {
      const images = message.attachments ?? []
      if (images.length && !model.input.includes('image')) throw new Error('This model does not support image input.')
      context.messages.push({ role: 'user', timestamp, content: [
        ...(message.content ? [{ type: 'text', text: message.content }] : []),
        ...images.map(({ data, mimeType }) => ({ type: 'image', data, mimeType })),
      ] })
    } else if (message.role === 'assistant') {
      for (const call of message.toolCalls ?? []) calls.set(call.id, call.name)
      const allowed = new Map((message.toolCalls ?? []).map((call) => [call.id, call]))
      // Keep opaque thinking signatures/response IDs intact. Reconcile tool
      // blocks with Dart's filtered history so interrupted calls stay excluded.
      const raw = message.providerMessage
      context.messages.push(raw ? {
        ...raw,
        content: raw.content.filter((block) => block.type !== 'toolCall' || allowed.has(block.id))
          .map((block) => block.type === 'toolCall' ? { ...block, ...allowed.get(block.id) } : block),
      } : {
        role: 'assistant', timestamp, api: model.api, provider: model.provider, model: model.id,
        content: [
          ...(message.content ? [{ type: 'text', text: message.content }] : []),
          ...(message.toolCalls ?? []).map((call) => ({ type: 'toolCall', ...call })),
        ],
        usage: zeroUsage(), stopReason: message.toolCalls?.length ? 'toolUse' : 'stop',
      })
    } else if (message.role === 'tool') {
      const toolName = calls.get(message.toolCallId)
      if (!toolName) throw new Error('Tool result has no matching tool call.')
      context.messages.push({ role: 'toolResult', timestamp, toolName,
        toolCallId: message.toolCallId, isError: message.isError ?? false,
        content: [{ type: 'text', text: message.content }],
      })
    }
  }
  return context
}

export async function invoke(request, emit, signal) {
  const model = resolveModel(request.settings)
  const models = createModels()
  const isCodex = model.provider === 'openai-codex'
  if (isCodex && !request.settings.credential) throw new Error('Sign in to OpenAI Codex first.')
  models.setProvider(createProvider({
    id: model.provider, models: [model], api: apis[model.api],
    auth: { apiKey: { name: 'HostDeck', resolve: async () => ({
      auth: isCodex ? await codexOAuth.toAuth(request.settings.credential) : {},
    }) } },
  }))
  const context = toContext(request.messages, request.tools, model)
  const stream = models.streamSimple(model, context, {
    ...(isCodex ? { transport: 'sse' } : { apiKey: request.settings.apiKey }), signal, maxTokens: Math.min(model.maxTokens, 4096),
  })
  for await (const event of stream) {
    if (event.type === 'text_delta') emit({ type: 'text', text: event.delta })
  }
  const message = await stream.result()
  if (message.stopReason === 'error' || message.stopReason === 'aborted') {
    throw new Error(message.errorMessage || `Model request ${message.stopReason}.`)
  }
  if (message.stopReason === 'length') throw new Error('Model output reached the token limit. Please shorten the request.')
  const toolCalls = message.content.filter((block) => block.type === 'toolCall').map((call) => ({
    id: call.id, name: call.name, arguments: validateToolCall(request.tools, call),
  }))
  emit({ type: 'result', text: message.content.filter((block) => block.type === 'text').map((block) => block.text).join(''),
    toolCalls, providerMessage: message,
    usage: {
      promptTokens: message.usage.input + message.usage.cacheRead + message.usage.cacheWrite,
      responseTokens: message.usage.output, totalTokens: message.usage.totalTokens,
      cacheReadTokens: message.usage.cacheRead, cacheWriteTokens: message.usage.cacheWrite,
      cost: message.usage.cost.total,
    },
  })
}

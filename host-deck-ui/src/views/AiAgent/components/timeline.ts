import type { AiAgentMessage, AiAgentRunStep } from '@/api/ai-agent'

export type AiAgentTimelineEntry =
  | { kind: 'message'; message: AiAgentMessage }
  | { kind: 'step'; step: AiAgentRunStep }

function entryTimestamp(value: number | string | undefined) {
  if (typeof value === 'number') return value
  if (typeof value === 'string') {
    return /^\d+$/.test(value) ? Number(value) : new Date(value).getTime()
  }
  return 0
}

function mergeByTimestamp(
  messageEntries: Array<{ entry: AiAgentTimelineEntry; timestamp: number }>,
  stepEntries: Array<{ entry: AiAgentTimelineEntry; timestamp: number }>,
) {
  const entries: AiAgentTimelineEntry[] = []
  let messageIndex = 0
  let stepIndex = 0
  while (messageIndex < messageEntries.length || stepIndex < stepEntries.length) {
    const message = messageEntries[messageIndex]
    const step = stepEntries[stepIndex]
    if (step === undefined || (message && message.timestamp <= step.timestamp)) {
      entries.push(messageEntries[messageIndex++]!.entry)
    } else {
      entries.push(stepEntries[stepIndex++]!.entry)
    }
  }
  return entries
}

export function buildTimelineEntries(
  messages: AiAgentMessage[],
  runSteps: AiAgentRunStep[],
): AiAgentTimelineEntry[] {
  if (runSteps.length === 0) {
    return messages.map((message) => ({ kind: 'message' as const, message }))
  }

  const currentAssistantIds = new Set(
    runSteps
      .filter((step) => step.type === 'model' && step.messageId)
      .map((step) => step.messageId),
  )
  const latestMessage = messages.at(-1)
  if (runSteps.some((step) => step.type === 'model') && latestMessage?.role === 'assistant') {
    currentAssistantIds.add(latestMessage.id)
  }

  const messageEntries = messages
    .filter((message) => !currentAssistantIds.has(message.id))
    .map((message) => ({
      entry: { kind: 'message' as const, message },
      timestamp: entryTimestamp(message.createdAt),
    }))

  const sortedSteps = [...runSteps].sort((a, b) => a.sequence - b.sequence)
  const stepEntries = sortedSteps
    .filter((step, index) => {
      if (step.type !== 'model' || step.content) return true
      // A tool follows this empty model step, so the tool call itself replaces
      // the pre-tool thinking placeholder to avoid a duplicate Agent loading.
      const hasLaterToolStep = sortedSteps
        .slice(index + 1)
        .some(({ type }) => type === 'tool' || type === 'approval')
      return !hasLaterToolStep
    })
    .map((step) => ({
      entry: { kind: 'step' as const, step },
      timestamp: entryTimestamp(step.startedAt),
    }))

  if (sortedSteps.every((step) => step.restored)) {
    return mergeByTimestamp(messageEntries, stepEntries)
  }
  return [...messageEntries.map((item) => item.entry), ...stepEntries.map((item) => item.entry)]
}

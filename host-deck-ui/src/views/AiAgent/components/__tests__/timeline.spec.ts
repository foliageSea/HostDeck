import { describe, expect, it } from 'vitest'
import type { AiAgentMessage, AiAgentRunStep } from '@/api/ai-agent'
import { buildTimelineEntries } from '../timeline'

function message(id: string, role: AiAgentMessage['role'], createdAt: number, extra: Partial<AiAgentMessage> = {}): AiAgentMessage {
  return {
    attachments: [],
    content: '',
    createdAt,
    id,
    role,
    ...extra,
  }
}

function restoredToolStep(callId: string, sequence: number, startedAt: number): AiAgentRunStep {
  return {
    callId,
    name: 'shell_execute',
    restored: true,
    runId: '',
    sequence,
    startedAt,
    status: 'success',
    stepId: `restored-${callId}`,
    type: 'tool',
  }
}

function liveStep(stepId: string, sequence: number): AiAgentRunStep {
  return {
    content: 'streamed',
    messageId: 'assistant-1',
    runId: 'run-1',
    sequence,
    startedAt: 90,
    status: 'running',
    stepId,
    type: 'model',
  }
}

describe('buildTimelineEntries', () => {
  it('renders an approval step and its tool step as one call', () => {
    const steps = [
      {
        callId: 'call-1',
        name: 'shell_execute',
        runId: 'run-1',
        sequence: 1,
        startedAt: 10,
        status: 'running',
        stepId: 'tool-1',
        type: 'tool',
      },
      {
        arguments: { command: 'uptime' },
        callId: 'call-1',
        name: 'shell_execute',
        runId: 'run-1',
        sequence: 2,
        startedAt: 11,
        status: 'waiting-approval',
        stepId: 'approval-1',
        type: 'approval',
      },
    ] satisfies AiAgentRunStep[]

    const entries = buildTimelineEntries([], steps)

    expect(entries).toHaveLength(1)
    expect(entries[0]).toMatchObject({
      kind: 'step',
      step: { callId: 'call-1', stepId: 'tool-1', type: 'tool' },
    })
  })

  it('hides the pre-tool empty model placeholder but keeps later thinking', () => {
    const emptyModelStep = (stepId: string, sequence: number): AiAgentRunStep => ({
      messageId: 'assistant-1',
      runId: 'run-1',
      sequence,
      startedAt: sequence * 10,
      status: 'running',
      stepId,
      type: 'model',
    })
    const steps = [
      emptyModelStep('model-before-tool', 0),
      restoredToolStep('call-1', 1, 10),
      emptyModelStep('model-after-tool', 2),
    ]

    const entries = buildTimelineEntries([], steps)

    expect(entries.map((entry) => (entry.kind === 'step' ? entry.step.stepId : entry.message.id))).toEqual([
      'restored-call-1',
      'model-after-tool',
    ])
  })

  it('returns plain messages when there are no steps', () => {
    const entries = buildTimelineEntries(
      [message('user-1', 'user', 1, { content: 'hi' })],
      [],
    )

    expect(entries).toEqual([{ kind: 'message', message: expect.objectContaining({ id: 'user-1' }) }])
  })

  it('merges restored tool steps between messages by timestamp', () => {
    const messages = [
      message('user-1', 'user', 10, { content: 'inspect' }),
      message('assistant-1', 'assistant', 40, { content: 'Done.' }),
      message('user-2', 'user', 50, { content: 'again' }),
      message('assistant-2', 'assistant', 60, { content: 'Sure.' }),
    ]
    const steps = [restoredToolStep('call-1', 0, 20), restoredToolStep('call-9', 1, 55)]

    const entries = buildTimelineEntries(messages, steps)

    expect(entries.map((entry) => entry.kind)).toEqual([
      'message',
      'step',
      'message',
      'message',
      'step',
      'message',
    ])
    expect(entries.map((entry) => (entry.kind === 'message' ? entry.message.id : entry.step.callId))).toEqual([
      'user-1',
      'call-1',
      'assistant-1',
      'user-2',
      'call-9',
      'assistant-2',
    ])
  })

  it('keeps live steps appended after messages', () => {
    const messages = [
      message('user-1', 'user', 100, { content: 'inspect' }),
      message('assistant-1', 'assistant', 101, { content: '' }),
    ]
    const steps = [liveStep('model-1', 0), restoredToolStep('call-1', 1, 90)]

    const entries = buildTimelineEntries(messages, steps)

    expect(entries.map((entry) => entry.kind)).toEqual(['message', 'step', 'step'])
    expect(entries[0]).toMatchObject({ kind: 'message', message: expect.objectContaining({ id: 'user-1' }) })
  })

  it('places a message before restored steps that share its timestamp', () => {
    const messages = [
      message('user-1', 'user', 10, { content: 'inspect' }),
      message('assistant-tool', 'assistant', 20, {
        content: 'Checking.',
        toolCalls: [{ id: 'call-1', name: 'shell_execute' }],
      }),
    ]
    const steps = [restoredToolStep('call-1', 0, 20)]

    const entries = buildTimelineEntries(messages, steps)

    expect(entries.map((entry) => (entry.kind === 'message' ? entry.message.id : entry.step.callId))).toEqual([
      'user-1',
      'assistant-tool',
      'call-1',
    ])
  })
})

import { describe, expect, it } from 'vitest'
import { consumeServerSentEvents } from '@/lib/sse'

describe('consumeServerSentEvents', () => {
  it('parses events split across byte chunks', async () => {
    const encoder = new TextEncoder()
    const chunks = [
      'event: phase\r\ndata: {"message":"准',
      '备"}\r\n\r\nevent: stdout\ndata: first\ndata: second\n\n',
    ]
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        for (const chunk of chunks) {
          controller.enqueue(encoder.encode(chunk))
        }
        controller.close()
      },
    })
    const events: Array<{ event: string; data: string }> = []

    await consumeServerSentEvents(stream, (event) => events.push(event))

    expect(events).toEqual([
      { event: 'phase', data: '{"message":"准备"}' },
      { event: 'stdout', data: 'first\nsecond' },
    ])
  })

  it('parses event ids and valid retry intervals without changing basic events', async () => {
    const encoder = new TextEncoder()
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(
          encoder.encode(
            'id: 42\nretry: 1500\nevent: log\ndata: {"message":"ready"}\n\n' +
              'retry: invalid\ndata: plain\n\n',
          ),
        )
        controller.close()
      },
    })
    const events: Array<{ event: string; data: string; id?: string; retry?: number }> = []

    await consumeServerSentEvents(stream, (event) => events.push(event))

    expect(events).toEqual([
      { event: 'log', data: '{"message":"ready"}', id: '42', retry: 1500 },
      { event: 'message', data: 'plain' },
    ])
  })
})

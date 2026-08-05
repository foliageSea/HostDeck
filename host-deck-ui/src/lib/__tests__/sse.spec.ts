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
})

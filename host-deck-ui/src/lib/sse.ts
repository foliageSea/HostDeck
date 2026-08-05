export interface ServerSentEvent {
  event: string
  data: string
}

function parseEventBlock(block: string): ServerSentEvent | null {
  let event = 'message'
  const data: string[] = []

  for (const line of block.split(/\r?\n/)) {
    if (!line || line.startsWith(':')) {
      continue
    }

    const separator = line.indexOf(':')
    const field = separator < 0 ? line : line.slice(0, separator)
    const value = separator < 0 ? '' : line.slice(separator + 1).replace(/^ /, '')
    if (field === 'event') {
      event = value
    } else if (field === 'data') {
      data.push(value)
    }
  }

  return data.length > 0 ? { event, data: data.join('\n') } : null
}

export async function consumeServerSentEvents(
  stream: ReadableStream<Uint8Array>,
  onEvent: (event: ServerSentEvent) => void,
) {
  const reader = stream.getReader()
  const decoder = new TextDecoder()
  let buffer = ''

  function drain(final = false) {
    while (true) {
      const boundary = buffer.search(/\r?\n\r?\n/)
      if (boundary < 0) {
        break
      }

      const block = buffer.slice(0, boundary)
      const separator = buffer.slice(boundary).match(/^\r?\n\r?\n/)?.[0] ?? '\n\n'
      buffer = buffer.slice(boundary + separator.length)
      const event = parseEventBlock(block)
      if (event) {
        onEvent(event)
      }
    }

    if (final && buffer.trim()) {
      const event = parseEventBlock(buffer)
      if (event) {
        onEvent(event)
      }
      buffer = ''
    }
  }

  try {
    while (true) {
      const { done, value } = await reader.read()
      if (done) {
        break
      }
      buffer += decoder.decode(value, { stream: true })
      drain()
    }
    buffer += decoder.decode()
    drain(true)
  } finally {
    reader.releaseLock()
  }
}

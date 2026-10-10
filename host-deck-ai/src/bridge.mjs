import { createInterface } from 'node:readline'
import { catalog, invoke } from './model.mjs'
import { loginCodex, refreshCodex } from './oauth.mjs'

const emit = (event) => process.stdout.write(`${JSON.stringify(event)}\n`)
const abort = new AbortController()
process.on('SIGTERM', () => {
  abort.abort()
  process.exit(0)
})
process.on('SIGINT', () => {
  abort.abort()
  process.exit(0)
})
const input = createInterface({ input: process.stdin, crlfDelay: Infinity })
try {
  // One request per process: process lifetime is the model request lifetime.
  for await (const line of input) {
    const request = JSON.parse(line)
    if (request.type === 'catalog') emit({ type: 'result', providers: catalog() })
    else if (request.type === 'oauth-login') await loginCodex(emit, abort.signal)
    else if (request.type === 'oauth-refresh')
      await refreshCodex(request.credential, emit, abort.signal)
    else await invoke(request, emit, abort.signal)
    break
  }
} catch (error) {
  // Do not pass upstream error bodies (which may echo credentials) over IPC.
  emit({
    type: 'error',
    message: 'pi-ai model request failed. Check provider, model, endpoint and API key.',
  })
  process.exitCode = 1
} finally {
  input.close()
  process.stdin.destroy()
}

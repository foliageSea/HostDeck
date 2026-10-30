const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { test } = require('node:test')
const { readDevHttps, readDevProxy } = require('../../../host-deck-ui/scripts/dev-tls.cjs')

test('development HTTPS is opt-in and requires both certificate files', () => {
  assert.equal(readDevHttps({}), undefined)
  assert.throws(() => readDevHttps({ HOSTDECK_DEV_TLS: 'yes' }), /true or false/)
  assert.throws(() => readDevHttps({ HOSTDECK_DEV_TLS: 'true' }), /CERT.*KEY/)
})

test('proxy reads the running backend protocol and preserves configured hosts', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hostdeck-dev-tls-'))
  try {
    const readyFile = path.join(directory, 'ready.json')
    fs.writeFileSync(readyFile, JSON.stringify({ baseUrl: 'http://127.0.0.1:9000' }))
    const env = { HOSTDECK_DEV_BACKEND_READY_FILE: readyFile }
    assert.equal(readDevProxy(env).target, 'http://127.0.0.1:9000')
    fs.writeFileSync(
      readyFile,
      JSON.stringify({ baseUrl: 'https://127.0.0.1:9000', certificatePem: 'test-certificate' }),
    )
    const secure = readDevProxy(env)
    assert.equal(secure.target, 'https://127.0.0.1:9000')
    assert.equal(secure.agent.options.ca, 'test-certificate')
    secure.agent.destroy()
    const ipv6 = readDevProxy({ ...env, HOSTDECK_DEV_BACKEND_HOST: '[::1]' })
    assert.equal(ipv6.target, 'https://[::1]:9000')
    ipv6.agent.destroy()
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

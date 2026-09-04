const assert = require('node:assert/strict')
const { EventEmitter } = require('node:events')
const test = require('node:test')

const { createChromeLauncher, parseLaunchRequest } = require('./chrome-launcher.cjs')

test('parseLaunchRequest accepts only HTTP targets and valid local proxy ports', () => {
  assert.deepEqual(
    parseLaunchRequest({
      profileId: 'tunnel_1',
      proxyPort: 49152,
      url: 'https://vault.internal/ui'
    }),
    { profileId: 'tunnel_1', proxyPort: 49152, url: 'https://vault.internal/ui' }
  )
  assert.throws(
    () => parseLaunchRequest({ profileId: 'tunnel_1', proxyPort: 49152, url: 'file:///tmp/a' }),
    /INVALID_URL/
  )
  assert.deepEqual(parseLaunchRequest({ profileId: 'tunnel_1', proxyPort: 49152 }), {
    profileId: 'tunnel_1',
    proxyPort: 49152,
    url: 'about:blank'
  })
  assert.throws(
    () => parseLaunchRequest({ profileId: '../escape', proxyPort: 49152, url: 'http://x/' }),
    /INVALID_PROFILE/
  )
})

test('launch starts an isolated Chrome instance with a fail-closed SOCKS proxy', async () => {
  const calls = []
  const child = new EventEmitter()
  child.unref = () => calls.push(['unref'])
  const launcher = createChromeLauncher({
    app: { getPath: () => '/hostdeck' },
    fileSystem: {
      constants: { X_OK: 1 },
      accessSync: () => undefined,
      mkdirSync: (...args) => calls.push(['mkdir', ...args])
    },
    processEnv: { HOME: '/user' },
    processPlatform: 'darwin',
    spawnProcess: (...args) => {
      calls.push(['spawn', ...args])
      queueMicrotask(() => child.emit('spawn'))
      return child
    }
  })

  assert.deepEqual(await launcher.launch({ profileId: 'tunnel-1', proxyPort: 49152 }), {
    success: true
  })
  const spawnCall = calls.find((call) => call[0] === 'spawn')
  assert.ok(spawnCall)
  assert.equal(spawnCall[1], '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
  assert.ok(spawnCall[2].includes('--user-data-dir=/hostdeck/secure-browser-profiles/tunnel-1'))
  assert.ok(spawnCall[2].includes('--proxy-server=socks5://127.0.0.1:49152'))
  assert.ok(spawnCall[2].includes('--proxy-bypass-list=<-loopback>'))
  assert.equal(spawnCall[2].includes('direct://'), false)
  assert.equal(spawnCall[2].at(-1), 'about:blank')
})

test('launch reports when Chrome is unavailable', async () => {
  const launcher = createChromeLauncher({
    app: { getPath: () => '/hostdeck' },
    fileSystem: {
      constants: { X_OK: 1 },
      accessSync: () => {
        throw new Error('missing')
      }
    },
    processEnv: {},
    processPlatform: 'linux'
  })

  assert.deepEqual(await launcher.launch({ profileId: 'tunnel-1', proxyPort: 49152 }), {
    success: false,
    reason: 'not-installed',
    message: '未检测到 Google Chrome。'
  })
})

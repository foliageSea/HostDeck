const assert = require('node:assert/strict')
const fs = require('node:fs/promises')
const os = require('node:os')
const path = require('node:path')
const { test } = require('node:test')
const afterPack = require('./after-pack.cjs')
const { setAppBuildUuid } = afterPack

function executable() {
  const binary = Buffer.alloc(72, 0xaa)
  binary.writeUInt32LE(0xfeedfacf, 0)
  binary.writeUInt32LE(0x100000c, 4)
  binary.writeUInt32LE(0, 8)
  binary.writeUInt32LE(2, 16)
  binary.writeUInt32LE(32, 20)
  binary.writeUInt32LE(0x1b, 32)
  binary.writeUInt32LE(24, 36)
  binary.writeUInt32LE(0x2a, 56)
  binary.writeUInt32LE(8, 60)
  return binary
}

test('changes only LC_UUID and preserves the other commands and executable data', () => {
  const binary = executable()
  const original = Buffer.from(binary)
  setAppBuildUuid(binary, 'com.foliagesea.hostdeck', '39.8.10')
  assert.deepEqual(binary.subarray(0, 40), original.subarray(0, 40))
  assert.notDeepEqual(binary.subarray(40, 56), original.subarray(40, 56))
  assert.deepEqual(binary.subarray(56), original.subarray(56))
})

test('UUID is repeatable and distinct across apps and Electron versions', () => {
  const binary = executable()
  const uuid = setAppBuildUuid(binary, 'com.foliagesea.hostdeck', '39.8.10')
  assert.equal(setAppBuildUuid(binary, 'com.foliagesea.hostdeck', '39.8.10'), uuid)
  assert.notEqual(setAppBuildUuid(executable(), 'com.electron.app', '39.8.10'), uuid)
  assert.notEqual(setAppBuildUuid(executable(), 'com.foliagesea.hostdeck', '39.8.11'), uuid)
})

test('rejects invalid or missing UUID commands before changing the executable', () => {
  for (const mutate of [
    (binary) => binary.writeUInt32LE(0, 0),
    (binary) => binary.writeUInt32LE(1000, 20),
    (binary) => binary.writeUInt32LE(0, 36),
    (binary) => binary.writeUInt32LE(0x2a, 32),
    (binary) => binary.writeUInt32LE(0x1b, 56),
  ]) {
    const binary = executable()
    mutate(binary)
    const original = Buffer.from(binary)
    assert.throws(() => setAppBuildUuid(binary, 'com.foliagesea.hostdeck', '39.8.10'))
    assert.deepEqual(binary, original)
  }
  assert.throws(() => setAppBuildUuid(Buffer.alloc(4), 'com.foliagesea.hostdeck', '39.8.10'))
})

test('leaves Windows packaging untouched', async () => {
  await afterPack({ electronPlatformName: 'win32' })
})

test('updates the packaged executable using the electron-builder hook context', async () => {
  const appOutDir = await fs.mkdtemp(path.join(os.tmpdir(), 'hostdeck-after-pack-'))
  try {
    const file = path.join(appOutDir, 'HostDeck.app', 'Contents', 'MacOS', 'HostDeck')
    await fs.mkdir(path.dirname(file), { recursive: true })
    await fs.writeFile(file, executable())
    await afterPack({
      appOutDir,
      electronPlatformName: 'darwin',
      packager: {
        appInfo: { macBundleIdentifier: 'com.foliagesea.hostdeck', productFilename: 'HostDeck' },
        config: { electronVersion: '39.8.10' },
      },
    })
    const expected = executable()
    setAppBuildUuid(expected, 'com.foliagesea.hostdeck', '39.8.10')
    assert.deepEqual(await fs.readFile(file), expected)
  } finally {
    await fs.rm(appOutDir, { recursive: true, force: true })
  }
})

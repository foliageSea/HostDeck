const assert = require('node:assert/strict')
const test = require('node:test')
const { prepareChromeProfile, usesProfile } = require('./chrome-profile.cjs')

test('matches profile paths with spaces without matching prefixes', () => {
  const directory = '/Application Support/host/host-123'
  assert.ok(usesProfile(`chrome --user-data-dir=${directory} --new-window`, directory))
  assert.ok(usesProfile(`chrome --user-data-dir="${directory}"`, directory))
  assert.equal(usesProfile(`chrome --user-data-dir=${directory}4`, directory), false)
})

test('reuses the same proxy and closes only the profile with an obsolete proxy', async () => {
  let processes = [
    {
      pid: 1,
      command: 'chrome --user-data-dir=/profiles/a --proxy-server=socks5://127.0.0.1:1234',
    },
    {
      pid: 2,
      command: 'chrome --user-data-dir=/profiles/b --proxy-server=socks5://127.0.0.1:1234',
    },
  ]
  const terminated = []
  const options = {
    listProcesses: async () => processes,
    terminate: async (pid) => {
      terminated.push(pid)
      processes = processes.filter((entry) => entry.pid !== pid)
    },
  }
  await prepareChromeProfile('/profiles/a', 1234, options)
  assert.deepEqual(terminated, [])
  await prepareChromeProfile('/profiles/a', 5678, options)
  assert.deepEqual(terminated, [1])
  assert.deepEqual(
    processes.map((entry) => entry.pid),
    [2],
  )
})

const { execFile } = require('node:child_process')
const { promisify } = require('node:util')
const { setTimeout: delay } = require('node:timers/promises')

const run = promisify(execFile)

function usesProfile(command, directory) {
  return [`--user-data-dir=${directory}`, `--user-data-dir="${directory}"`].some(
    (argument) => command.endsWith(argument) || command.includes(`${argument} `),
  )
}

async function listChromeProcesses() {
  if (process.platform === 'win32') {
    const { stdout } = await run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      'ConvertTo-Json -Compress -InputObject @(Get-CimInstance Win32_Process -Filter "Name = \'chrome.exe\'" | Select-Object ProcessId,CommandLine)',
    ])
    return JSON.parse(stdout).map((entry) => ({
      pid: entry.ProcessId,
      command: entry.CommandLine || '',
    }))
  }
  const { stdout } = await run('/bin/ps', ['-axww', '-o', 'pid=,args='])
  return stdout.split('\n').flatMap((line) => {
    const match = line.match(/^\s*(\d+)\s+(.+)$/)
    return match ? [{ pid: Number(match[1]), command: match[2] }] : []
  })
}

async function prepareChromeProfile(
  directory,
  proxyPort,
  {
    listProcesses = listChromeProcesses,
    terminate = async (pid) => {
      if (process.platform === 'win32') {
        await run('taskkill.exe', ['/PID', String(pid), '/T'])
      } else {
        process.kill(pid, 'SIGTERM')
      }
    },
  } = {},
) {
  const matches = (await listProcesses()).filter(
    ({ command }) => usesProfile(command, directory) && !command.includes('--type='),
  )
  const proxyArgument = `--proxy-server=socks5://127.0.0.1:${proxyPort}`
  const stale = matches.filter(({ command }) => !command.split(/\s+/).includes(proxyArgument))
  for (const { pid } of stale) {
    try {
      await terminate(pid)
    } catch (error) {
      if (error.code !== 'ESRCH') throw error
    }
  }
  for (let attempt = 0; stale.length && attempt < 100; attempt++) {
    const remaining = (await listProcesses()).some(
      ({ command }) => usesProfile(command, directory) && !command.includes('--type='),
    )
    if (!remaining) return
    await delay(100)
  }
  if (stale.length) throw new Error('请关闭此主机的安全浏览器窗口后重试。')
}

module.exports = { prepareChromeProfile, usesProfile }

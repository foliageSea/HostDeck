const fs = require('node:fs')
const path = require('node:path')
const { spawn } = require('node:child_process')

function isValidProfileId(value) {
  return typeof value === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(value)
}

function parseLaunchRequest(request) {
  if (!request || typeof request !== 'object') throw new Error('INVALID_REQUEST')

  let url = 'about:blank'
  if (request.url != null) {
    try {
      const parsedUrl = new URL(request.url)
      if (
        !['http:', 'https:'].includes(parsedUrl.protocol) ||
        parsedUrl.username ||
        parsedUrl.password
      ) {
        throw new Error('INVALID_URL')
      }
      url = parsedUrl.toString()
    } catch {
      throw new Error('INVALID_URL')
    }
  }

  const proxyPort = Number(request.proxyPort)
  if (!Number.isInteger(proxyPort) || proxyPort < 1 || proxyPort > 65535) {
    throw new Error('INVALID_PROXY')
  }
  if (!isValidProfileId(request.profileId)) throw new Error('INVALID_PROFILE')

  return { profileId: request.profileId, proxyPort, url }
}

function chromeCandidates(platform, env) {
  if (platform === 'win32') {
    return [
      env.PROGRAMFILES &&
        path.join(env.PROGRAMFILES, 'Google', 'Chrome', 'Application', 'chrome.exe'),
      env['PROGRAMFILES(X86)'] &&
        path.join(env['PROGRAMFILES(X86)'], 'Google', 'Chrome', 'Application', 'chrome.exe'),
      env.LOCALAPPDATA &&
        path.join(env.LOCALAPPDATA, 'Google', 'Chrome', 'Application', 'chrome.exe')
    ].filter(Boolean)
  }
  if (platform === 'darwin') {
    return [
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      env.HOME &&
        path.join(
          env.HOME,
          'Applications',
          'Google Chrome.app',
          'Contents',
          'MacOS',
          'Google Chrome'
        )
    ].filter(Boolean)
  }
  return ['/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/usr/local/bin/google-chrome']
}

function createChromeLauncher({
  app,
  fileSystem = fs,
  processEnv = process.env,
  processPlatform = process.platform,
  spawnProcess = spawn
}) {
  function findChrome() {
    return chromeCandidates(processPlatform, processEnv).find((candidate) => {
      try {
        fileSystem.accessSync(candidate, fileSystem.constants.X_OK)
        return true
      } catch {
        return false
      }
    })
  }

  async function launch(request) {
    let parsed
    try {
      parsed = parseLaunchRequest(request)
    } catch (error) {
      return { success: false, reason: 'invalid-request', message: error.message }
    }

    const executable = findChrome()
    if (!executable) {
      return { success: false, reason: 'not-installed', message: '未检测到 Google Chrome。' }
    }

    const profileDirectory = path.join(
      app.getPath('userData'),
      'secure-browser-profiles',
      parsed.profileId
    )
    fileSystem.mkdirSync(profileDirectory, { recursive: true })
    const args = [
      `--user-data-dir=${profileDirectory}`,
      `--proxy-server=socks5://127.0.0.1:${parsed.proxyPort}`,
      '--proxy-bypass-list=<-loopback>',
      '--no-first-run',
      '--no-default-browser-check',
      '--new-window',
      parsed.url
    ]

    try {
      const child = spawnProcess(executable, args, {
        detached: true,
        stdio: 'ignore',
        windowsHide: true
      })
      await new Promise((resolve, reject) => {
        child.once('error', reject)
        child.once('spawn', resolve)
      })
      child.unref()
      return { success: true }
    } catch (error) {
      return {
        success: false,
        reason: 'launch-failed',
        message: error instanceof Error ? error.message : String(error)
      }
    }
  }

  return { launch }
}

module.exports = { createChromeLauncher, parseLaunchRequest }

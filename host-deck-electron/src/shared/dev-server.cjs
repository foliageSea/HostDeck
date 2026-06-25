const http = require('node:http')
const path = require('node:path')

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function normalizeUrl(url) {
  return String(url || '').replace(/\/$/, '')
}

function portToUrl(port, fallbackPort) {
  const value = Number(port)
  const nextPort = Number.isInteger(value) && value > 0 && value <= 65535 ? value : fallbackPort
  return `http://localhost:${nextPort}`
}

async function resolveConfiguredDevUrl({ configFile, envVarName, fallbackPort }) {
  if (process.env[envVarName]) return normalizeUrl(process.env[envVarName])

  try {
    const { resolveConfig } = await import('vite')
    const config = await resolveConfig(
      {
        configFile,
        root: path.dirname(configFile),
      },
      'serve'
    )
    return portToUrl(config.server?.port, fallbackPort)
  } catch (error) {
    console.warn(`Unable to resolve Vite dev server URL from ${configFile}:`, error)
    return portToUrl(undefined, fallbackPort)
  }
}

function ping(url) {
  return new Promise((resolve, reject) => {
    const request = http.get(url, (response) => {
      response.resume()
      resolve()
    })
    request.on('error', reject)
    request.setTimeout(1000, () => request.destroy(new Error('timeout')))
  })
}

async function waitForUrl(url, timeoutMs = 30000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    try {
      await ping(url)
      return
    } catch {
      await sleep(300)
    }
  }
  throw new Error(`Server did not start: ${url}`)
}

module.exports = {
  normalizeUrl,
  resolveConfiguredDevUrl,
  waitForUrl,
}

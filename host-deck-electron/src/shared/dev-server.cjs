const http = require('node:http')
const https = require('node:https')
const path = require('node:path')
const { probeOptions } = require('../main/backend-tls.cjs')
const devCertificates = new Map()

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function normalizeUrl(url) {
  return String(url || '').replace(/\/$/, '')
}

function portToUrl(port, fallbackPort, secure = false, host = 'localhost') {
  const value = Number(port)
  const nextPort = Number.isInteger(value) && value > 0 && value <= 65535 ? value : fallbackPort
  const hostname =
    typeof host === 'string' && !['0.0.0.0', '::'].includes(host) ? host : 'localhost'
  return `${secure ? 'https' : 'http'}://${hostname.includes(':') ? `[${hostname}]` : hostname}:${nextPort}`
}

async function resolveConfiguredDevUrl({ configFile, envVarName, fallbackPort }) {
  const { resolveConfig } = await import('vite')
  const config = await resolveConfig(
    {
      configFile,
      root: path.dirname(configFile),
    },
    'serve',
  )
  const url = process.env[envVarName]
    ? normalizeUrl(process.env[envVarName])
    : portToUrl(
        config.server?.port,
        fallbackPort,
        Boolean(config.server?.https),
        config.server?.host,
      )
  const certificate = config.server?.https?.cert
  if (certificate && new URL(url).protocol === 'https:') {
    devCertificates.set(new URL(url).origin, String(certificate))
  } else {
    devCertificates.delete(new URL(url).origin)
  }
  return url
}

function devCertificate(url) {
  return devCertificates.get(new URL(url).origin)
}

function configureDevTrust(session, urls) {
  const trusted = urls
    .filter(Boolean)
    .map((url) => ({
      hostname: new URL(url).hostname.replace(/^\[|\]$/g, ''),
      pem: devCertificate(url),
    }))
    .filter((entry) => entry.pem)
  const { X509Certificate } = require('node:crypto')
  const { certificateMatches } = require('../main/backend-tls.cjs')
  session.setCertificateVerifyProc((request, callback) => {
    try {
      const fingerprint = new X509Certificate(request.certificate.data).fingerprint256
      if (
        trusted.some(
          (entry) =>
            entry.hostname === request.hostname && certificateMatches(entry.pem, fingerprint),
        )
      ) {
        callback(0)
        return
      }
    } catch {}
    callback(-3)
  })
}

function ping(url, options = {}) {
  return new Promise((resolve, reject) => {
    const transport = new URL(url).protocol === 'https:' ? https : http
    const request = transport.get(url, options, (response) => {
      response.resume()
      resolve()
    })
    request.on('error', reject)
    request.setTimeout(1000, () => request.destroy(new Error('timeout')))
  })
}

async function waitForUrl(url, timeoutMs = 30000, options) {
  options ??= probeOptions(devCertificate(url))
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    try {
      await ping(url, options)
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
  configureDevTrust,
}

const fs = require('node:fs')
const path = require('node:path')
const https = require('node:https')

function readDevHttps(env = process.env, root = process.cwd()) {
  const enabled = env.HOSTDECK_DEV_TLS
  if (enabled && !['true', 'false'].includes(enabled)) {
    throw new Error('HOSTDECK_DEV_TLS must be true or false')
  }
  if (enabled !== 'true') return undefined
  if (!env.HOSTDECK_DEV_TLS_CERT || !env.HOSTDECK_DEV_TLS_KEY) {
    throw new Error('Development TLS requires HOSTDECK_DEV_TLS_CERT and HOSTDECK_DEV_TLS_KEY')
  }
  return {
    cert: fs.readFileSync(path.resolve(root, env.HOSTDECK_DEV_TLS_CERT)),
    key: fs.readFileSync(path.resolve(root, env.HOSTDECK_DEV_TLS_KEY)),
    minVersion: 'TLSv1.2',
  }
}

function readDevProxy(env = process.env, root = process.cwd()) {
  let target = env.VITE_DEV_PROXY_TARGET || 'http://localhost:8080'
  let certificatePem
  if (env.HOSTDECK_DEV_BACKEND_READY_FILE) {
    const ready = JSON.parse(
      fs.readFileSync(path.resolve(root, env.HOSTDECK_DEV_BACKEND_READY_FILE), 'utf8'),
    )
    if (typeof ready.baseUrl !== 'string') throw new Error('Invalid development backend ready file')
    target = ready.baseUrl
    certificatePem = ready.certificatePem
  }
  const url = new URL(target)
  if (env.HOSTDECK_DEV_BACKEND_HOST) url.hostname = env.HOSTDECK_DEV_BACKEND_HOST
  if (!['http:', 'https:'].includes(url.protocol))
    throw new Error('Invalid development backend URL')
  if (env.HOSTDECK_DEV_PROXY_CA_CERT) {
    certificatePem = fs.readFileSync(path.resolve(root, env.HOSTDECK_DEV_PROXY_CA_CERT), 'utf8')
  }
  const agent =
    url.protocol === 'https:' && certificatePem
      ? new https.Agent({ ca: certificatePem, allowPartialTrustChain: true })
      : undefined
  return { target: url.href.replace(/\/$/, ''), agent }
}

module.exports = { readDevHttps, readDevProxy }

import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { createRequire } from 'node:module'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import http from 'node:http'
import https from 'node:https'
import tls from 'node:tls'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { test } from 'node:test'
import { createServer } from 'vite'

const require = createRequire(import.meta.url)
const {
  resolveConfiguredDevUrl,
  waitForUrl,
  configureDevTrust,
} = require('../../host-deck-electron/src/shared/dev-server.cjs')
const root = fileURLToPath(new URL('../', import.meta.url))

function request(url, ca) {
  return new Promise((resolve, reject) => {
    const transport = url.startsWith('https:') ? https : http
    transport
      .get(url, { ca }, (response) => {
        let body = ''
        response.on('data', (chunk) => {
          body += chunk
        })
        response.on('end', () => resolve({ status: response.statusCode, body }))
      })
      .on('error', reject)
  })
}

function upgrade(url, ca, pathname, protocol) {
  const target = new URL(url)
  return new Promise((resolve, reject) => {
    const socket = tls.connect(
      { host: '127.0.0.1', servername: 'localhost', port: Number(target.port), ca },
      () => {
        socket.write(
          `GET ${pathname} HTTP/1.1\r\nHost: localhost:${target.port}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n${protocol ? `Sec-WebSocket-Protocol: ${protocol}\r\n` : ''}\r\n`,
        )
      },
    )
    socket.setTimeout(3000, () => socket.destroy(new Error('WebSocket upgrade timed out')))
    socket.once('data', (data) => {
      socket.destroy()
      resolve(data.toString())
    })
    socket.on('error', reject)
  })
}

test(
  'Vite serves HTTPS, HMR/WSS and switches proxy from HTTP to verified HTTPS',
  { timeout: 60000 },
  async () => {
    const directory = mkdtempSync(path.join(os.tmpdir(), 'hostdeck-vite-tls-'))
    const originalEnv = { ...process.env }
    const servers = []
    let vite
    let shell
    try {
      execFileSync(
        'openssl',
        [
          'req',
          '-x509',
          '-newkey',
          'rsa:2048',
          '-nodes',
          '-keyout',
          `${directory}/key.pem`,
          '-out',
          `${directory}/cert.pem`,
          '-days',
          '1',
          '-subj',
          '/CN=localhost',
          '-addext',
          'subjectAltName=DNS:localhost,IP:127.0.0.1',
        ],
        { stdio: 'ignore' },
      )
      const cert = readFileSync(`${directory}/cert.pem`)
      const key = readFileSync(`${directory}/key.pem`)
      const responder = (_, response) => response.end('backend-ok')
      const plain = http.createServer(responder)
      const secure = https.createServer({ cert, key }, responder)
      for (const server of [plain, secure]) {
        servers.push(server)
        server.on('upgrade', (_, socket) => {
          socket.end(
            'HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n',
          )
        })
        await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
      }
      const readyFile = `${directory}/ready.json`
      writeFileSync(
        readyFile,
        JSON.stringify({ baseUrl: `http://127.0.0.1:${plain.address().port}` }),
      )
      Object.assign(process.env, {
        HOSTDECK_DEV_TLS: 'true',
        HOSTDECK_DEV_TLS_CERT: `${directory}/cert.pem`,
        HOSTDECK_DEV_TLS_KEY: `${directory}/key.pem`,
        HOSTDECK_DEV_BACKEND_READY_FILE: readyFile,
      })
      vite = await createServer({
        root,
        configFile: `${root}/vite.config.ts`,
        server: { port: 0, host: '127.0.0.1' },
        optimizeDeps: { noDiscovery: true, include: [] },
        logLevel: 'error',
      })
      await vite.listen()
      const url = `https://localhost:${vite.httpServer.address().port}`
      assert.equal((await request(url, cert)).status, 200)
      assert.equal((await request(`${url}/src/main.ts`, cert)).status, 200)
    assert.equal((await request(`${url}/api/status`, cert)).body, 'backend-ok')
    assert.equal((await request(`${url}/wallpapers/desktop.png`, cert)).body, 'backend-ok')
      const token = vite.config.webSocketToken
      assert.match(
        await upgrade(url, cert, `/?token=${token}`, 'vite-hmr'),
        /101 Switching Protocols/,
      )
      assert.match(await upgrade(url, cert, '/api/ws/terminal'), /101 Switching Protocols/)
      writeFileSync(
        readyFile,
        JSON.stringify({
          baseUrl: `https://127.0.0.1:${secure.address().port}`,
          certificatePem: String(cert),
        }),
      )
      const deadline = Date.now() + 10000
      while (vite.config.server.proxy['/api'].target.startsWith('http:')) {
        if (Date.now() > deadline) throw new Error('Vite proxy did not switch to HTTPS')
        await new Promise((resolve) => setTimeout(resolve, 100))
      }
      await new Promise((resolve) => setTimeout(resolve, 300))
      assert.equal((await request(`${url}/api/status`, cert)).body, 'backend-ok')
      assert.match(await upgrade(url, cert, '/api/ws/terminal'), /101 Switching Protocols/)
      const detected = await resolveConfiguredDevUrl({
        configFile: `${root}/vite.config.ts`,
        envVarName: 'HOSTDECK_TEST_UNSET_DEV_URL',
        fallbackPort: 5178,
      })
      assert.equal(detected, 'https://localhost:5178')
      process.env.HOST_DECK_ELECTRON_APP_DEV_URL = url
      const resolved = await resolveConfiguredDevUrl({
        configFile: `${root}/vite.config.ts`,
        envVarName: 'HOST_DECK_ELECTRON_APP_DEV_URL',
        fallbackPort: 5178,
      })
      assert.equal(resolved, url)
      await waitForUrl(resolved, 3000)
      let verifier
      configureDevTrust(
        {
          setCertificateVerifyProc: (value) => {
            verifier = value
          },
        },
        [resolved],
      )
      verifier({ hostname: 'localhost', certificate: { data: String(cert) } }, (result) =>
        assert.equal(result, 0),
      )
      verifier({ hostname: 'example.com', certificate: { data: String(cert) } }, (result) =>
        assert.equal(result, -3),
      )
      const shellRoot = path.resolve(root, '../host-deck-electron')
      shell = await createServer({
        root: shellRoot,
        configFile: `${shellRoot}/vite.config.mjs`,
        server: { port: 0, host: '127.0.0.1' },
        optimizeDeps: { noDiscovery: true, include: [] },
        logLevel: 'error',
      })
      await shell.listen()
      assert.equal(
        (
          await request(
            `https://localhost:${shell.httpServer.address().port}/src/renderer/loading.html`,
            cert,
          )
        ).status,
        200,
      )
    } finally {
      if (vite) await vite.close()
      if (shell) await shell.close()
      await Promise.all(
        servers.map(
          (server) =>
            new Promise((resolve) => {
              server.closeAllConnections()
              server.close(resolve)
            }),
        ),
      )
      for (const key of Object.keys(process.env)) if (!(key in originalEnv)) delete process.env[key]
      Object.assign(process.env, originalEnv)
      rmSync(directory, { recursive: true, force: true })
    }
  },
)
